package org.floxy
{
	public class ProxyClassInfo
	{
		public function ProxyClassInfo(proxiedClass:Class, proxiedNamespaces:Array, proxyClass:Class)
		{
			_proxiedClass = proxiedClass;
			_proxiedNamespaces = proxiedNamespaces;
			_proxyClass = proxyClass;
		}
		
		private var _proxiedClass:Class;
		
		public function get proxiedClass():Class 
		{
			return _proxiedClass;
		}

		private var _proxiedNamespaces:Array;
		
		public function get proxiedNamespaces():Array 
		{
			return _proxiedNamespaces;
		}
		
		private var _proxyClass:Class;
		
		public function get proxyClass():Class
		{
			return _proxyClass
		}
	}
}