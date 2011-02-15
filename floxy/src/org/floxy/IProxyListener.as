package org.floxy
{
	public interface IProxyListener
	{
		function methodExecuted(target : Object, methodType : uint, methodName : String, ns:String, arguments : Array, baseMethod : Function) : *;
	}
}