package org.floxy
{
	import org.flemit.reflection.*;
	
	public interface IInvocation
	{
		function get arguments() : Array;
		function get targetType() : Type;
		
		function get proxy() : Object;
		function get method() : MethodInfo;
		function get property() : PropertyInfo;
		
		function get invocationTarget() : Object;
		function get methodInvocationTarget() : MethodInfo;
		
		function get returnValue() : Object;
		function set returnValue(value : Object) : void;
		
		function get canProceed() : Boolean;
		function proceed() : void;
	}
}