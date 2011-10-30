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
	import org.floxy.event.ProxyClassEvent;
	
	/**
	 * Prepares and creates instances of proxy implementations of classes and interfaces.
	 */
	public class ProxyRepository implements IProxyRepository
	{
		private var _proxyGenerator:ProxyGenerator;
		private var _proxies:Dictionary;
		private var _loaders:Array;
		private var _preparers:Array;
		
		public function ProxyRepository()
		{
			_proxyGenerator = new ProxyGenerator();
			
			_loaders = [];
			_proxies = new Dictionary();
			_preparers = [];
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
//			trace("ProxyRepository.create", cls, args);
			
			var proxyClass:Class = _proxies[cls];
			if (proxyClass == null)
			{
				throw new ArgumentError("A proxy for "
					+ getQualifiedClassName(cls) + " has not been prepared yet");
			}
			
			return createWithProxyClass(proxyClass, args, interceptor);			
		}
		
		/**
		 * @private
		 */
		public function createWithProxyClass(proxyClass:Class, args:Array, interceptor:IInterceptor):Object 
		{
//			trace("ProxyRepository.createWithProxyClass", proxyClass, args);
			
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
			
//			trace("ProxyRepository.prepare", classes);
			
			var classesToPrepare:Array = filterAlreadyPreparedClasses(classes);
			
			if (classesToPrepare.length == 0)
			{
//				trace("ProxyRepository.prepare already prepared", classes);
				
				return new CompletedEventDispatcher();
			}
			
			var dynamicClasses:Array = new Array();
			
			var layoutBuilder:IByteCodeLayoutBuilder = new ByteCodeLayoutBuilder();
			
			var generatedNames:Dictionary = new Dictionary();
			
			for each (var cls:Class in classesToPrepare)
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
				
//				trace("ProxyRepository.prepare proxy", qname.toString());
				
				generatedNames[cls] = qname;
				
				var dynamicClass:DynamicClass = (type.isInterface)
					? _proxyGenerator.createProxyFromInterface(qname, [ type ])
					: _proxyGenerator.createProxyFromClass(qname, type, [], []);
				
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
			_preparers.push(eventDispatcher); 
			
			return eventDispatcher;
			
			function swfErrorHandler(error:ErrorEvent):void
			{
//				trace("ProxyRepository.prepare error generating swf: " + error.text);
				
				_loaders.splice(_loaders.indexOf(error.target), 1);
				_preparers.splice(_preparers.indexOf(eventDispatcher), 1);
				
				eventDispatcher.dispatchEvent(error);
			}
			
			function swfLoadedHandler(event:Event):void
			{
				for each (var cls:Class in classesToPrepare)
				{
					var qname:QualifiedName = generatedNames[cls];
					
					var fullName:String = qname.ns.name.concat('::', qname.name);
					
					var generatedClass:Class = loader.contentLoaderInfo.applicationDomain.getDefinition(fullName) as Class;
					
					Type.getType(generatedClass);
					
					_proxies[cls] = generatedClass;
					
//					trace("ProxyRepository prepare loaded", cls, generatedClass);
					var proxyClassInfo:ProxyClassInfo = new ProxyClassInfo(cls, null, generatedClass);
					
					eventDispatcher.dispatchEvent(new ProxyClassEvent(proxyClassInfo));
				}
				
				eventDispatcher.dispatchEvent(new Event(Event.COMPLETE));
				
				_loaders.splice(_loaders.indexOf(event.target), 1);
				_preparers.splice(_preparers.indexOf(eventDispatcher), 1);
			}
		}
		
		/**
		 * @private
		 */
		public function prepareClasses(classes:Array, applicationDomain:ApplicationDomain = null):IEventDispatcher
		{
			applicationDomain = applicationDomain || new ApplicationDomain(ApplicationDomain.currentDomain);
			
//			trace("ProxyRepository.prepareClasses", classes.length, classes);
			
			var classesToPrepare:Array = classes;
			if (classesToPrepare.length == 0)
			{
//				trace("ProxyRepository.prepareClasses no classes to prepare", classes);
				return new CompletedEventDispatcher();
			}
			
			var dynamicClasses:Array = new Array();
			var layoutBuilder:IByteCodeLayoutBuilder = new ByteCodeLayoutBuilder();
			
			for each (var item:Array in classesToPrepare)
			{
				var classToPrepare:Class = item[0];
				var namespacesToProxy:Array = prepareNamespacesToProxy(item[1] || []);
				
//				trace("ProxyRepository.prepareClasses classToPrepare", classToPrepare);
//				trace("ProxyRepository.prepareClasses namespacesToProxy", namespacesToProxy);
				
				var type:Type = Type.getType(classToPrepare);
				if (type.isGeneric || type.isGenericTypeDefinition)
				{
					throw new IllegalOperationError("Generic types (Vector) are not supported. (feature request #2599097)");
				}
				
				if (type.qname.ns.kind != NamespaceKind.PACKAGE_NAMESPACE)
				{
					throw new IllegalOperationError("Private (package) classes are not supported. (feature request #2549289)");
				}
				
				var qname:QualifiedName = generateQName(type);
				
//				trace("ProxyRepository.prepareClasses proxy", qname.toString());
				
				item[2] = qname;
				
				var dynamicClass:DynamicClass = (type.isInterface)
					? _proxyGenerator.createProxyFromInterface(qname, [ type ])
					: _proxyGenerator.createProxyFromClass(qname, type, [], namespacesToProxy);
				
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
			_preparers.push(eventDispatcher); 
			
			return eventDispatcher;
			
			function swfErrorHandler(error:ErrorEvent):void
			{
//				trace("ProxyRepository.prepareClasses error generating swf: " + error.text);
				
				_loaders.splice(_loaders.indexOf(error.target), 1);
				_preparers.splice(_preparers.indexOf(eventDispatcher), 1);
				
				eventDispatcher.dispatchEvent(error);
			}
			
			function swfLoadedHandler(event:Event):void
			{
				for each (var item:Array in classesToPrepare)
				{
//					trace("ProxyRepository.prepareClasses loaded item", item);
					
					var classToPrepare:Class = item[0];
					var namespacesToProxy:Array = item[1] || [];
					var qname:QualifiedName = item[2];
					var fullName:String = qname.ns.name.concat('::', qname.name);
					
//					trace("ProxyRepository.prepareClasses loaded", fullName);
					var generatedClass:Class = loader.contentLoaderInfo.applicationDomain.getDefinition(fullName) as Class;
					
					Type.getType(generatedClass);
					
					_proxies[classToPrepare] = generatedClass;
					
//					trace("ProxyRepository.prepareClasses loaded", classToPrepare, generatedClass);
					var proxyClassInfo:ProxyClassInfo = new ProxyClassInfo(classToPrepare, namespacesToProxy, generatedClass);
					
					eventDispatcher.dispatchEvent(new ProxyClassEvent(proxyClassInfo));
				}
				
				eventDispatcher.dispatchEvent(new Event(Event.COMPLETE));
				
				_loaders.splice(_loaders.indexOf(event.target), 1);
				_preparers.splice(_preparers.indexOf(eventDispatcher), 1);
			}
		}
		
		/**
		 * @private
		 */
		public function prepareClass(classReference:Class, namespacesToProxy:Array = null, applicationDomain:ApplicationDomain = null):IEventDispatcher 
		{
			applicationDomain = applicationDomain || new ApplicationDomain(ApplicationDomain.currentDomain);
			
			var preparedNamespaces:Array = prepareNamespacesToProxy(namespacesToProxy);
			
			var type:Type = Type.getType(classReference);

			if (type.isGeneric || type.isGenericTypeDefinition)
			{
				throw new IllegalOperationError("Generic types (Vector) are not supported. (feature request #2599097)");
			}
			
			if (type.qname.ns.kind != NamespaceKind.PACKAGE_NAMESPACE)
			{
				throw new IllegalOperationError("Private (package) classes are not supported. (feature request #2549289)");
			}
			
			var qname:QualifiedName = generateQName(type);
			
//			trace("ProxyRepository.prepareClass", qname.toString());
			
			var dynamicClass:DynamicClass = (type.isInterface)
				? _proxyGenerator.createProxyFromInterface(qname, [ type ])
				: _proxyGenerator.createProxyFromClass(qname, type, [], preparedNamespaces);
			
			var layoutBuilder:IByteCodeLayoutBuilder = new ByteCodeLayoutBuilder();
			
			layoutBuilder.registerType(dynamicClass);
			layoutBuilder.registerType(Type.getType(IProxyListener));
			
			var layout:IByteCodeLayout = layoutBuilder.createLayout();
			
			var loader:Loader = createSwf(layout, applicationDomain);
			_loaders.push(loader);
			loader.contentLoaderInfo.addEventListener(Event.COMPLETE, swfLoadedHandler);
			loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, swfErrorHandler);
			loader.contentLoaderInfo.addEventListener(ErrorEvent.ERROR, swfErrorHandler);
			
			var eventDispatcher:EventDispatcher = new EventDispatcher();
			_preparers.push(eventDispatcher);
			
			return eventDispatcher;
			
			function swfErrorHandler(error:ErrorEvent):void
			{
//				trace("ProxyRepository.prepareClass error generating swf: " + error.text);
				
				eventDispatcher.dispatchEvent(error);
				
				_loaders.splice(_loaders.indexOf(error.target), 1);
				_preparers.splice(_preparers.indexOf(eventDispatcher), 1);
			}
			
			function swfLoadedHandler(event:Event):void
			{
				var fullName:String = qname.ns.name.concat('::', qname.name);
				var generatedClass:Class = loader.contentLoaderInfo.applicationDomain.getDefinition(fullName) as Class;
				
				Type.getType(generatedClass);
					
				_proxies[classReference] = generatedClass;
				
				var proxyClassInfo:ProxyClassInfo = new ProxyClassInfo(classReference, namespacesToProxy, generatedClass);
				
//				trace("ProxyRepository.prepareClass", classReference, generatedClass);
				eventDispatcher.dispatchEvent(new ProxyClassEvent(proxyClassInfo));
				
				eventDispatcher.dispatchEvent(new Event(Event.COMPLETE));
				
				_loaders.splice(_loaders.indexOf(event.target), 1);
				_preparers.splice(_preparers.indexOf(eventDispatcher), 1);				
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
			var kind:uint = type.qname.ns.kind;
			var useTypePackage:Boolean 
				= kind != NamespaceKind.PACKAGE_NAMESPACE; 
//				|| kind != NamespaceKind.PUBLIC_NAMESPACE;
			
			var ns:BCNamespace 
				= useTypePackage
				? type.qname.ns
				: BCNamespace.packageNS("mockolate.generated");
				
			return new QualifiedName(ns, type.name + GUID.create());
		}
		
		private function filterAlreadyPreparedClasses(classes:Array):Array 
		{
			return classes.filter(typeAlreadyPreparedFilter);
		}
		
		private function typeAlreadyPreparedFilter(cls:Class, index:int, array:Array):Boolean
		{
			return (_proxies[cls] == null);
		}
		
		private function prepareNamespacesToProxy(namespacesToProxy:Array):Array
		{
			namespacesToProxy ||= [];
			namespacesToProxy = filterNamespacesToProxy(namespacesToProxy);
			namespacesToProxy = pluckNamespaceURI(namespacesToProxy);
			namespacesToProxy = sortNamespaceToProxy(namespacesToProxy);
			return namespacesToProxy;
		}
		
		private function filterNamespacesToProxy(namespacesToProxy:Array):Array
		{
			return namespacesToProxy.filter(function(ns:*, i:int, a:Array):Boolean {
				return ns is Namespace;
			})
		}
		
		private function pluckNamespaceURI(namespacesToProxy:Array):Array
		{
			return namespacesToProxy.map(function(ns:Namespace, i:int, a:Array):String {
				return ns.uri;
			})
		}
		
		private function sortNamespaceToProxy(namespacesToProxy:Array):Array 
		{
			return namespacesToProxy.sort(Array.CASEINSENSITIVE);
		}
	}
}

import flash.events.IEventDispatcher;
import flash.events.EventDispatcher;
import flash.events.Event;

internal class CompletedEventDispatcher extends EventDispatcher
{
	public override function addEventListener(
		type:String, 
		listener:Function, 
		useCapture:Boolean = false, 
		priority:int = 0, 
		useWeakReference:Boolean = false):void
	{
		super.addEventListener(type, listener, useCapture, priority, useWeakReference);
		
		if (type == Event.COMPLETE)
		{
			dispatchEvent(new Event(Event.COMPLETE));
			
			super.removeEventListener(type, listener, useCapture);
		}
	}
}