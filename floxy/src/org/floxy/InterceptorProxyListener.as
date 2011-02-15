package org.floxy
{
	import org.flemit.reflection.*;
	
	internal class InterceptorProxyListener implements IProxyListener
	{
		private var _constructed:Boolean = false;
		
		private var _interceptor:IInterceptor;
		
		private var _proxyClass:Class;
		private var _proxyType:Type;
		
		public function InterceptorProxyListener(interceptor:IInterceptor, proxyClass:Class)
		{
			_interceptor = interceptor;
			_proxyClass = proxyClass;
			_proxyType = Type.getType(proxyClass);
		}
		
		public function methodExecuted(target:Object, methodType:uint, methodName:String, ns:String, arguments:Array, baseMethod:Function):*
		{
			if (methodType == MethodType.CONSTRUCTOR)
			{
				_constructed = true;
				return;
			}
			
			if (!_constructed)
			{
				if (baseMethod != null)
				{
					baseMethod.apply(null, arguments);
				}
				
				return;
			}
			
			// var targetType:Type = Type.getType(target);
			var targetType:Type = _proxyType;
			var method:MethodInfo;
			var property:PropertyInfo;
			
			switch (methodType)
			{
				case MethodType.METHOD:
					method = targetType.getMethod(methodName, ns, true);
					break;
				case MethodType.PROPERTY_GET:
					property = targetType.getProperty(methodName, ns, true);
					method = property.getMethod;
					break;
				case MethodType.PROPERTY_SET:
					property = targetType.getProperty(methodName, ns, true);
					method = property.setMethod;
					break;
			}
			
			var invocation:IInvocation = new SimpleInvocation(target, property, method, arguments, baseMethod);
			
			_interceptor.intercept(invocation);
			
			return invocation.returnValue;
		}
	}
}