package org.floxy.testSupport
{
	public class FloxyNamespaceSupport
	{
		public function FloxyNamespaceSupport()
		{
		}
		
		public function isProxied():Boolean
		{
			return false;
		}
		
		test_support function isProxyingNamespacesSupported():Boolean 
		{
			return false;
		}
	}
}