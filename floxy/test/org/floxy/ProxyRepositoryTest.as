package org.floxy
{
	import flash.events.Event;
	import flash.events.IEventDispatcher;
	import flash.utils.getDefinitionByName;
	import flash.utils.getQualifiedClassName;
	
	import mx.events.PropertyChangeEvent;
	
	import org.flexunit.assertThat;
	import org.flexunit.async.Async;
	import org.floxy.event.ProxyClassEvent;
	import org.floxy.testSupport.FloxyNamespaceSupport;
	import org.floxy.testSupport.test_support;
	import org.hamcrest.core.not;
	import org.hamcrest.object.equalTo;
	import org.hamcrest.object.instanceOf;
	import org.hamcrest.object.notNullValue;

	public class ProxyRepositoryTest
	{
		public var repository:ProxyRepository;
		public var namespaces:Array;
		public var dispatcher:IEventDispatcher;
		
		[Test(async)]
		public function prepareClass_withNoNamespaces_shouldPrepareClass():void 
		{
			repository = new ProxyRepository();
			namespaces = [];
			dispatcher = repository.prepareClass(FloxyNamespaceSupport, namespaces);
			
			Async.handleEvent(this, dispatcher, ProxyClassEvent.PROXY_CLASS_PREPARED, proxyClassPrepared);
			
			function proxyClassPrepared(event:ProxyClassEvent, data:Object):void {
				var instance:* = repository.createWithProxyClass(event.proxyClassInfo.proxyClass, [], null);
				assertThat(instance, instanceOf(FloxyNamespaceSupport));
			}
		}
		
		[Test(async)]
		public function prepareClass_withNamespaces_shouldPrepareClass():void 
		{
			repository = new ProxyRepository();
			namespaces = [ test_support ];
			dispatcher = repository.prepareClass(FloxyNamespaceSupport, namespaces);
			
			Async.handleEvent(this, dispatcher, ProxyClassEvent.PROXY_CLASS_PREPARED, proxyClassPrepared);
			
			function proxyClassPrepared(event:ProxyClassEvent, data:Object):void {
				var instance:* = repository.createWithProxyClass(event.proxyClassInfo.proxyClass, [], null);
				assertThat(instance, instanceOf(FloxyNamespaceSupport));
			}
		}
		
		[Test(async)]
		public function prepareClasses():void 
		{
			repository = new ProxyRepository();
			dispatcher = repository.prepareClasses([
				[ FloxyNamespaceSupport ],
				[ FloxyNamespaceSupport, [ test_support ]]
			]);
			
			var f1Proxy:Class;
			var f2Proxy:Class;
			
			dispatcher.addEventListener(ProxyClassEvent.PROXY_CLASS_PREPARED, function(event:ProxyClassEvent):void {
				if (event.proxyClassInfo.proxiedNamespaces.length == 0)
					f1Proxy = event.proxyClassInfo.proxyClass;
				else 
					f2Proxy = event.proxyClassInfo.proxyClass;
			});
			
			Async.handleEvent(this, dispatcher, Event.COMPLETE, proxyClassesPrepared);
			
			function proxyClassesPrepared(event:Event, data:Object):void {
				var f1:FloxyNamespaceSupport = repository.createWithProxyClass(f1Proxy, null, null) as FloxyNamespaceSupport;
				var f2:FloxyNamespaceSupport = repository.createWithProxyClass(f2Proxy, null, null) as FloxyNamespaceSupport;
				
				assertThat(f1, notNullValue());
				assertThat(f2, notNullValue());
				assertThat(f1, not(equalTo(f2)));
			}
		}
		
		[Test(async)]
		public function prepareClasses_withIEventDispatcher():void 
		{
			repository = new ProxyRepository();
			dispatcher = repository.prepareClasses([
				[ IEventDispatcher ]
			]);
			
			Async.handleEvent(this, dispatcher, Event.COMPLETE, proxyClassesPrepared);
			
			function proxyClassesPrepared(event:Event, data:Object):void {
				var instance:IEventDispatcher = repository.create(IEventDispatcher, null, null) as IEventDispatcher;
				assertThat(instance, notNullValue());
			}
		}
	}
}