package org.floxy
{
	import flash.events.IEventDispatcher;
	import flash.system.ApplicationDomain;
	
	/**
	 * Prepares and creates instances of proxy implementations of classes and interfaces.
	 */
	public interface IProxyRepository
	{
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
		function create(cls : Class, args : Array, interceptor : IInterceptor) : Object;
		
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
		function prepare(classes : Array, applicationDomain : ApplicationDomain = null) : IEventDispatcher;
		
		/**
		 * @private
		 */
		function prepareClass(classReference:Class, namespacesToProxy:Array = null, applicationDomain:ApplicationDomain = null):IEventDispatcher
	}
}