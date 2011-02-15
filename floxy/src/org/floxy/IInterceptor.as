package org.floxy
{
	public interface IInterceptor
	{
		function intercept(invocation : IInvocation) : void;		
	}
}