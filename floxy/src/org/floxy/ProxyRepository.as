package org.floxy
{
	import flash.display.Loader;
	import flash.errors.IllegalOperationError;
	import flash.events.*;
	import flash.system.ApplicationDomain;
	import flash.system.LoaderContext;
	import flash.utils.ByteArray;
	import flash.utils.Dictionary;
	import flash.utils.getQualifiedClassName;
	
	import org.flemit.*;
	import org.flemit.bytecode.*;
	import org.flemit.reflection.Type;
	import org.flemit.tags.*;
	import org.flemit.util.ClassUtility;
	import org.flemit.util.MethodUtil;
	
	/**
	 * Prepares and creates instances of proxy implementations of classes and interfaces.
	 */
	public class ProxyRepository implements IProxyRepository
	{
		private var _proxyGenerator:ProxyGenerator;
		
		private var _proxies:Dictionary;
		
		private var _loaders:Array;
		
		public function ProxyRepository()
		{
			_proxyGenerator = new ProxyGenerator();
			
			_loaders = new Array();
			_proxies = new Dictionary();
		}
		
		/**
		 * Creates an instance of a proxy. The proxy must already have been
		 * prepared by calling prepare.
		 * @param cls The class to create a proxy instance for
		 * @param args The arguments to pass to the base constructor
		 * @param interceptor The interceptor that will receive calls from the proxy
		 * @return An instance of the class specified by the cls argument
		 * @throws ArgumentException Thrown when a proxy for the cls argument has not been prepared by
		 * calling prepare
		 */
		public function create(cls:Class, args:Array, interceptor:IInterceptor):Object
		{
			var proxyClass:Class = _proxies[cls];
			
			if (proxyClass == null)
			{
				throw new ArgumentError("A proxy for "
					+ getQualifiedClassName(cls) + " has not been prepared yet");
			}
			
			var proxyListener:IProxyListener = new InterceptorProxyListener(interceptor, proxyClass);
			var constructorArgCount:int = Type.getType(proxyClass).constructor.parameters.length;
			var constructorRequiredArgCount:int = MethodUtil.getRequiredArgumentCount(Type.getType(proxyClass).constructor);
			
			args = [ proxyListener ].concat(args);
			
			if (args.length > ClassUtility.MAX_CREATECLASS_ARG_COUNT)
			{
				if (args.length != constructorArgCount)
				{
					throw new ArgumentError("Constructors with more than " + ClassUtility.MAX_CREATECLASS_ARG_COUNT + " arguments must supply the exact number of arguments (including optional).");
				}
				
				var createMethod:Function = proxyClass[ProxyGenerator.CREATE_METHOD];
				
				return createMethod.apply(proxyClass, args) as Object;
			}
			else
			{
				if (args.length < constructorRequiredArgCount)
				{
					throw new ArgumentError("Incorrect number of constructor arguments supplied.");
				}
				
				return ClassUtility.createClass(proxyClass, args);
			}
		}
		
		/**
		 * Prepares proxies for multiple classes into the specified application domain.
		 *
		 * The method will return an IEventDispatcher that will dispatch a Event.COMPLETE
		 * when the preparation completes, or ErrorEvent.ERROR if there is an error
		 * during preparation.
		 *
		 * Proxies will not be generated for classes that were previously prepared by this
		 * repository. If all classes in the classes argument has already been prepared,
		 * the IEventDispatcher that is returned will automatically dispatch Event.COMPLETE
		 * whenever it is subsribed to.
		 *
		 * Please note that verification errors during load (caused by incompatible
		 * clases or a bug in floxy) will not raise an ErrorEvent, but instead throw an
		 * uncatchable VerifyError. This is a bug in Flash player that has been logged
		 * as <a href="http://bugs.adobe.com/jira/browse/FP-1619">FP-1619</a>
		 *
		 * Do not supply a new parent ApplicationDomain as the applicationDomain argument. Doing
		 * so will cause the preparation to fail, since class bodies of non-proxy classes are
		 * included in the dynamic SWF.
		 *
		 * @param classes An array of Class objects to prepare proxies for
		 * @param applicationDomain The application domain to load the dynamic proxies into. If not specified,
		 * a child application domain will be created from the current domain.
		 * @return An IEventDispatcher that will dispatch a Event.COMPLETE when the preparation completes,
		 * or ErrorEvent.ERROR if there is an error during preparation
		 */
		public function prepare(classes:Array, applicationDomain:ApplicationDomain = null):IEventDispatcher
		{
			applicationDomain = applicationDomain || new ApplicationDomain(ApplicationDomain.currentDomain);
			
			classes = classes.filter(typeAlreadyPreparedFilter);
			
			if (classes.length == 0)
			{
				return new CompletedEventDispatcher();
			}
			
			var dynamicClasses:Array = new Array();
			
			var layoutBuilder:IByteCodeLayoutBuilder = new ByteCodeLayoutBuilder();
			
			var generatedNames:Dictionary = new Dictionary();
			
			for each (var cls:Class in classes)
			{
				var type:Type = Type.getType(cls);
				
				if (type.isGeneric || type.isGenericTypeDefinition)
				{
					throw new IllegalOperationError("Generic types (Vector) are not supported. (feature request #2599097)");
				}
				
				if (type.qname.ns.kind != NamespaceKind.PACKAGE_NAMESPACE)
				{
					throw new IllegalOperationError("Private (package) classes are not supported. (feature request #2549289)");
				}
				
				var qname:QualifiedName = generateQName(type);
				
				generatedNames[cls] = qname;
				
				var dynamicClass:DynamicClass = (type.isInterface)
					? _proxyGenerator.createProxyFromInterface(qname, [ type ])
					: _proxyGenerator.createProxyFromClass(qname, type, []);
				
				layoutBuilder.registerType(dynamicClass);
			}
			
			layoutBuilder.registerType(Type.getType(IProxyListener));
			
			var layout:IByteCodeLayout = layoutBuilder.createLayout();
			
			var loader:Loader = createSwf(layout, applicationDomain);
			_loaders.push(loader);
			loader.contentLoaderInfo.addEventListener(Event.COMPLETE, swfLoadedHandler);
			loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, swfErrorHandler);
			loader.contentLoaderInfo.addEventListener(ErrorEvent.ERROR, swfErrorHandler);
			
			var eventDispatcher:EventDispatcher = new EventDispatcher();
			
			return eventDispatcher;
			
			function swfErrorHandler(error:ErrorEvent):void
			{
				trace("Error generating swf: " + error.text);
				
				eventDispatcher.dispatchEvent(error);
			}
			
			function swfLoadedHandler(event:Event):void
			{
				for each (var cls:Class in classes)
				{
					var qname:QualifiedName = generatedNames[cls];
					
					var fullName:String = qname.ns.name.concat('::', qname.name);
					
					var generatedClass:Class = loader.contentLoaderInfo.applicationDomain.getDefinition(fullName) as Class;
					
					Type.getType(generatedClass);
					
					_proxies[cls] = generatedClass;
				}
				
				eventDispatcher.dispatchEvent(new Event(Event.COMPLETE));
			}
		}
		
		private function createSwf(layout:IByteCodeLayout, applicationDomain:ApplicationDomain):Loader
		{
			var buffer:ByteArray = new ByteArray();
			
			var header:SWFHeader = new SWFHeader(10);
			
			var swfWriter:SWFWriter = new SWFWriter();
			
			swfWriter.write(buffer, header, [
				FileAttributesTag.create(false, false, false, true, true),
				new ScriptLimitsTag(),
				new SetBackgroundColorTag(0xFF, 0x0, 0x0),
				new FrameLabelTag("ProxyFrameLabel"),
				new DoABCTag(false, "ProxyGenerated", layout),
				new ShowFrameTag(),
				new EndTag()
				]);
			
			buffer.position = 0;
			
			var loaderContext:LoaderContext = new LoaderContext(false, applicationDomain);
			
			enableAIRDynamicExecution(loaderContext);
			
			var loader:Loader = new Loader();
			loader.loadBytes(buffer, loaderContext);
			
			return loader;
		}
		
		private function enableAIRDynamicExecution(loaderContext:LoaderContext):void
		{
			// Needed for AIR
			if (loaderContext.hasOwnProperty("allowLoadBytesCodeExecution"))
			{
				loaderContext["allowLoadBytesCodeExecution"] = true;
			}
		}
		
		private function generateQName(type:Type):QualifiedName
		{
			var ns:BCNamespace = (type.qname.ns.kind != NamespaceKind.PACKAGE_NAMESPACE)
				? type.qname.ns
				: BCNamespace.packageNS("asmock.generated");
			
			return new QualifiedName(ns, type.name + GUID.create());
		}
		
		private function typeAlreadyPreparedFilter(cls:Class, index:int, array:Array):Boolean
		{
			return (_proxies[cls] == null);
		}
	}
}
import flash.events.IEventDispatcher;
import flash.events.EventDispatcher;
import flash.events.Event;


class CompletedEventDispatcher extends EventDispatcher
{
	public override function addEventListener(type:String, listener:Function, useCapture:Boolean = false, priority:int = 0, useWeakReference:Boolean =
		false):void
	{
		super.addEventListener(type, listener, useCapture, priority, useWeakReference);
		
		if (type == Event.COMPLETE)
		{
			dispatchEvent(new Event(Event.COMPLETE));
			
			super.removeEventListener(type, listener, useCapture);
		}
	}
}