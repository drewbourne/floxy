package org.floxy.event
{
	import flash.events.Event;
	
	import org.floxy.ProxyClassInfo;

	public class ProxyClassEvent extends Event
	{
		public static const PROXY_CLASS_PREPARED:String = "ProxyClassEvent.PROXY_CLASS_PREPARED";
		
		public function ProxyClassEvent(proxyClassInfo:ProxyClassInfo)
		{
			super(PROXY_CLASS_PREPARED, false, false);
			
			_proxyClassInfo = proxyClassInfo;
		}
		
		private var _proxyClassInfo:ProxyClassInfo;
		
		public function get proxyClassInfo():ProxyClassInfo 
		{
			return _proxyClassInfo;
		}
		
		override public function clone():Event
		{
			return new ProxyClassEvent(proxyClassInfo);
		}
	}
}