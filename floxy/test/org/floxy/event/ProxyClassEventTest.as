package org.floxy.event
{
	import flash.events.Event;
	
	import org.floxy.ProxyClassInfo;
	import org.hamcrest.assertThat;
	import org.hamcrest.core.not;
	import org.hamcrest.object.equalTo;
	import org.hamcrest.object.hasProperties;
	import org.hamcrest.object.instanceOf;

	public class ProxyClassEventTest
	{
		[Test]
		public function clone_shouldCopyEventProperties():void 
		{
			const proxiedClass:Class = UnusedClass;
			const proxiedNamespaces:Array = [];
			const proxyClass:Class = UnusedProxyClass;
			
			const info:ProxyClassInfo = new ProxyClassInfo(
				proxiedClass,
				proxiedNamespaces, 
				proxyClass);
			
			const event:ProxyClassEvent = new ProxyClassEvent(info);
			
			const clone:Event = event.clone();

			assertThat(clone, instanceOf(ProxyClassEvent));
			assertThat(clone, not(equalTo(event)));
			assertThat(clone, hasProperties({ proxyClassInfo: info }));
		}
	}
}

internal class UnusedClass {}
internal class UnusedProxyClass {}