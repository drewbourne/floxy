package org.floxy
{
	import org.flemit.bytecode.*;
	import org.flemit.reflection.*;
	
	internal class ProxyGenerator
	{
		public static const CREATE_METHOD : String = "__createInstance";
		
		private var proxyListenerType : Type = Type.getType(IProxyListener);
		
		public function ProxyGenerator()
		{
		}
		
		public function createProxyFromInterface(qname : QualifiedName, interfaces : Array) : DynamicClass
		{
//			trace("ProxyRepository.createProxyFromInterface", qname, interfaces);
			
			var superClass : Type = Type.getType(Object);
			
			var dynamicClass : DynamicClass = new DynamicClass(qname, superClass, interfaces);
			
			addInterfaceMembers(dynamicClass);
			
			var method : MethodInfo;
			var property : PropertyInfo;
			
			dynamicClass.constructor = createConstructor(dynamicClass);
			
			dynamicClass.addSlot(new FieldInfo(dynamicClass, PROXY_FIELD_NAME, qname.toString() + "/" + PROXY_FIELD_NAME, MemberVisibility.PUBLIC, false, Type.getType(IProxyListener)));
			
			dynamicClass.addMethodBody(dynamicClass.scriptInitialiser, generateScriptInitialiser(dynamicClass));
			dynamicClass.addMethodBody(dynamicClass.staticInitialiser, generateStaticInitialiser(dynamicClass));
			dynamicClass.addMethodBody(dynamicClass.constructor, generateInitialiser(dynamicClass));
			
			for each(method in dynamicClass.getMethods())
			{
				dynamicClass.addMethodBody(method, generateMethod(dynamicClass, method, null, false, method.name, MethodType.METHOD));
			}
			
			for each(property in dynamicClass.getProperties())
			{
				dynamicClass.addMethodBody(property.getMethod, generateMethod(dynamicClass, property.getMethod, null, false, property.name, MethodType.PROPERTY_GET));
				dynamicClass.addMethodBody(property.setMethod, generateMethod(dynamicClass, property.setMethod, null, false, property.name, MethodType.PROPERTY_SET));
			}
			
			var createInstanceMethodBody : DynamicMethod = generateCreateInstanceMethod(dynamicClass);
			dynamicClass.addMethod(createInstanceMethodBody.method);
			dynamicClass.addMethodBody(createInstanceMethodBody.method, createInstanceMethodBody);
			
			return dynamicClass;
		}
		
		public function createProxyFromClass(qname : QualifiedName, superClass : Type, interfaces : Array, namespacesToProxy:Array) : DynamicClass
		{
//			trace('ProxyGenerator.createProxyFromClass class', qname, interfaces, namespacesToProxy);
			
			var dynamicClass : DynamicClass = new DynamicClass(qname, superClass, interfaces);
			
			var method : MethodInfo;
			var property : PropertyInfo;
			
			addSuperClassMembers(dynamicClass, namespacesToProxy);
			
			dynamicClass.constructor = createConstructor(dynamicClass);
			
			dynamicClass.addSlot(new FieldInfo(dynamicClass, PROXY_FIELD_NAME, qname.toString() + "/" + PROXY_FIELD_NAME, MemberVisibility.PUBLIC, false, Type.getType(IProxyListener)));
			
			dynamicClass.addMethodBody(dynamicClass.scriptInitialiser, generateScriptInitialiser(dynamicClass));
			dynamicClass.addMethodBody(dynamicClass.staticInitialiser, generateStaticInitialiser(dynamicClass));
			dynamicClass.addMethodBody(dynamicClass.constructor, generateInitialiser(dynamicClass));
			
			for each (method in dynamicClass.getMethods())
			{
//				trace('ProxyGenerator.createProxyFromClass method', method.qname);
				
				var baseMethod : MethodInfo = (method.isStatic)
					? null 
					: superClass.getMethod(method.name, method.ns, true);
				
				dynamicClass.addMethodBody(method, generateMethod(dynamicClass, method, baseMethod, false, method.name, MethodType.METHOD));
			}
			
			for each (property in dynamicClass.getProperties())
			{
//				trace('ProxyGenerator.createProxyFromClass property', property.qname);
				
				var baseProperty : PropertyInfo = (property.isStatic)
					? null
					: superClass.getProperty(property.name, property.ns, true);
				
				var baseGetDynamicMethod : DynamicMethod = null, 
					baseSetDynamicMethod : DynamicMethod = null;
				
				var baseGetMethod : MethodInfo = null,
					baseSetMethod : MethodInfo = null;
				
				if (baseProperty != null)
				{
					if (baseProperty.canRead)
					{
						baseGetDynamicMethod = generateSuperPropertyGetterMethod(property);
						baseGetMethod = baseGetDynamicMethod.method;
						
						dynamicClass.addMethod(baseGetDynamicMethod.method);
						dynamicClass.addMethodBody(baseGetDynamicMethod.method, baseGetDynamicMethod);
						
						dynamicClass.addMethodBody(property.getMethod, generateMethod(dynamicClass, property.getMethod, baseGetMethod, true, property.name, MethodType.PROPERTY_GET));
					}
					
					if (baseProperty.canWrite)
					{
						baseSetDynamicMethod = generateSuperPropertySetterMethod(property);
						baseSetMethod = baseSetDynamicMethod.method; 
						
						dynamicClass.addMethod(baseSetDynamicMethod.method);
						dynamicClass.addMethodBody(baseSetDynamicMethod.method, baseSetDynamicMethod);
						
						dynamicClass.addMethodBody(property.setMethod, generateMethod(dynamicClass, property.setMethod, baseSetMethod, true, property.name, MethodType.PROPERTY_SET));
					}
				}
			}
			
			var createInstanceMethodBody : DynamicMethod = generateCreateInstanceMethod(dynamicClass);
			dynamicClass.addMethod(createInstanceMethodBody.method);
			dynamicClass.addMethodBody(createInstanceMethodBody.method, createInstanceMethodBody);
			
			return dynamicClass;
		}
		
		private function addInterfaceMembers(dynamicClass : DynamicClass) : void
		{
			var allInterfaces : Array = dynamicClass.getInterfaces();
			
			for each(var inter : Type in allInterfaces)
			{
				for each(var extendedInterface : Type in inter.getInterfaces())
				{
					if (allInterfaces.indexOf(extendedInterface) == -1)
					{
						allInterfaces.push(extendedInterface);
					}
				}
				
				for each(var method : MethodInfo in inter.getMethods())
				{
					if (dynamicClass.getMethod(method.name) == null)
					{					
						dynamicClass.addMethod(new MethodInfo(dynamicClass, method.name, null, method.visibility, method.isStatic, false, method.returnType, method.parameters));
					}
				}
				
				for each(var property : PropertyInfo in inter.getProperties())
				{
					if (dynamicClass.getProperty(property.name) == null)
					{
						dynamicClass.addProperty(new PropertyInfo(dynamicClass, property.name, null, property.visibility, property.isStatic, false, property.type, property.canRead, property.canWrite));
					}
				}
			}
		}
		
		private function addSuperClassMembers(dynamicClass : DynamicClass, namespacesToProxy:Array) : void
		{
			var superClass : Type = dynamicClass.baseType;
			var objectType : Type = Type.getType(Object);
			
//			trace("ProxyGenerator.addSuperClassMembers dynamicClass addSuper", dynamicClass.name, namespacesToProxy);
			
			while (superClass != objectType)
			{
//				trace("ProxyGenerator.addSuperClassMembers superClass", superClass.name);
				
				for each (var method : MethodInfo in superClass.getMethods(false, true))
				{
//					trace("ProxyGenerator.addSuperClassMembers method", method.ns, method.name, 
//						dynamicClass.getMethod(method.name, method.ns, false) == null
//						&& (!method.ns || namespacesToProxy.indexOf(method.ns) != -1));
					
					if (dynamicClass.getMethod(method.name, method.ns, false) == null
						&& (!method.ns || namespacesToProxy.indexOf(method.ns) != -1))
					{
						// TODO: IsFinal?
						dynamicClass.addMethod(new MethodInfo(dynamicClass, method.name, null, method.visibility, method.isStatic, true, method.returnType, method.parameters, method.ns));
					}
				}
				
				for each(var property : PropertyInfo in superClass.getProperties(false, true))
				{
//					trace("ProxyGenerator.addSuperClassMembers property", property.ns, property.name, !property.ns, namespacesToProxy.indexOf(property.ns));
					
					if (dynamicClass.getProperty(property.name, property.ns, false) == null
						&& (!property.ns || namespacesToProxy.indexOf(property.ns) != -1))
					{
						// TODO: IsFinal?
						dynamicClass.addProperty(new PropertyInfo(dynamicClass, property.name, null, property.visibility, property.isStatic, true, property.type, property.canRead, property.canWrite, property.ns));
					}
				}
				
				superClass = superClass.baseType;
			}
		}
		
		private function createConstructor(dynamicClass : DynamicClass) : MethodInfo
		{
			var baseCtor : MethodInfo = dynamicClass.baseType.constructor;
			
			var params : Array = new Array().concat(baseCtor.parameters);
			params.unshift(new ParameterInfo("_proxy", Type.getType(IProxyListener), false));
			
			//return new MethodInfo(dynamicClass, dynamicClass.name, null, MemberVisibility.PUBLIC, false, 
			return new MethodInfo(dynamicClass, "ctor", null, MemberVisibility.PUBLIC, false, false, 
				Type.star, params);
		}
		
		private function generateScriptInitialiser(dynamicClass : DynamicClass) : DynamicMethod
		{
			var clsNamespaceSet : NamespaceSet = new NamespaceSet(
				[new BCNamespace(dynamicClass.packageName, NamespaceKind.PACKAGE_NAMESPACE)]);
			
//			trace("ProxyGenerator.generateScriptInitialiser dynamicClass ", dynamicClass.qname, dynamicClass.isInterface);
//			trace("ProxyGenerator.generateScriptInitialiser clsNamespaceSet", clsNamespaceSet);
//			trace("ProxyGenerator.generateScriptInitialiser multiNamespaceName", dynamicClass.multiNamespaceName);
			
			var op:Instructions = Instructions.instance;
			
			if (dynamicClass.isInterface)
			{
				return new DynamicMethod(dynamicClass.scriptInitialiser, 3, 2, 1, 3, [
					[ op.GetLocal_0 ],
					[ op.PushScope ],
					[ op.FindPropertyStrict, new MultipleNamespaceName(dynamicClass.name, clsNamespaceSet) ], 
					[ op.PushNull ],
					[ op.NewClass, dynamicClass ],
					[ op.InitProperty, dynamicClass.qname ],
					[ op.ReturnVoid ]
				]); 
			}
			else
			{
				// TODO: Support where base class is not Object
				return new DynamicMethod(dynamicClass.scriptInitialiser, 3, 2, 1, 3, [
					[ op.GetLocal_0 ],
					[ op.PushScope ],
					//[GetScopeObject, 0],
					[ op.FindPropertyStrict, dynamicClass.multiNamespaceName ], 
					[ op.GetLex, dynamicClass.baseType.qname ],
					[ op.PushScope ],
					[ op.GetLex, dynamicClass.baseType.qname ],
					[ op.NewClass, dynamicClass ],
					[ op.PopScope ],
					[ op.InitProperty, dynamicClass.qname ],
					[ op.ReturnVoid ]
				]);
			}
		}
		
		private function generateStaticInitialiser(dynamicClass : DynamicClass) : DynamicMethod
		{
			var op:Instructions = Instructions.instance;
			
			return new DynamicMethod(dynamicClass.staticInitialiser, 2, 2, 3, 4, [
				[ op.GetLocal_0 ],
				[ op.PushScope ],
				[ op.ReturnVoid ]
			]);
		}
		
		private function generateInitialiser(dynamicClass : DynamicClass) : DynamicMethod
		{
			var baseCtor : MethodInfo = dynamicClass.baseType.constructor;
			var argCount : uint = baseCtor.parameters.length;
			var proxyField : FieldInfo = dynamicClass.getField(PROXY_FIELD_NAME,null);
			var op:Instructions = Instructions.instance;
			
			var instructions : Array = [
				[ op.GetLocal_0 ],
				[ op.PushScope ],
				
				[ op.FindProperty, proxyField.qname ],
				[ op.GetLocal_1 ], // proxy argument (always first arg)
				[ op.InitProperty, proxyField.qname ],
				
				// begin construct super
				[ op.GetLocal_0 ] // 'this'
			];
			
			for (var i:uint=0; i<argCount; i++) 
			{
				instructions.push([ op.GetLocal, i + 2 ]);
			}
			
			instructions.push(
				[ op.ConstructSuper, argCount ],
				// end construct super
			
				// call __proxy__.methodExecuted(this, CONSTRUCTOR, className, ns, {arguments})
				[ op.GetLocal_1 ],
				[ op.GetLocal_0 ],
				[ op.PushByte, MethodType.CONSTRUCTOR ],
				[ op.PushString, dynamicClass.name ],
				[ op.PushNull ],
				[ op.GetLocal, argCount + 2 ], // 'arguments'
				[ op.PushNull ],
				[ op.CallPropVoid, proxyListenerType.getMethod("methodExecuted").qname, 6 ],
				
				[ op.ReturnVoid ]
			);
				
			return new DynamicMethod(dynamicClass.constructor, 7 + argCount, 3 + argCount, 4, 5, instructions);
		}
		
		private function generateMethod(dynamicClass : DynamicClass, method : MethodInfo, baseMethod : MethodInfo, baseIsDelegate : Boolean, name : String, methodType : uint) : DynamicMethod
		{
			var argCount : uint = method.parameters.length;
			var proxyField : FieldInfo = dynamicClass.getField(PROXY_FIELD_NAME,null);
			var ns:String = method.ns;
			var op:Instructions = Instructions.instance;
			
			var instructions : Array = [
				[op.GetLocal_0],
				[op.PushScope],
				
				[op.GetLex, proxyField.qname],
				[op.GetLocal_0],
				[op.PushByte, methodType],
				[op.PushString, name],
				[op.PushString, ns],
				[op.GetLocal, argCount + 1], // 'arguments'					
			];
			
			// TODO: IsFinal?
			if (baseMethod != null)
			{
				if (baseIsDelegate)
				{
					instructions.push(
						[op.GetLex, baseMethod.qname]
					);
				}
				else
				{
					instructions.push(
						[op.GetLocal_0],
						[op.GetSuper, baseMethod.qname]
					);
				}
			}
			else
			{
				instructions.push(
					[op.PushNull]
				);
			}
			
			instructions.push(
				[op.CallProperty, proxyListenerType.getMethod("methodExecuted").qname, 6]
			);
			
			if (method.returnType == Type.voidType) // void
			{
				instructions.push(
					[op.ReturnVoid]
				);
			}
			else
			{
				instructions.push(
					[op.ReturnValue]
				);
			}
			
			return new DynamicMethod(method, 8 + argCount, argCount + 2, 4, 5, instructions);
		}
		
		private function generateSuperPropertyGetterMethod(property : PropertyInfo) : DynamicMethod
		{
			var method : MethodInfo = new MethodInfo(property.owner, "get_" + property.name + "_internal", null, MemberVisibility.PRIVATE, false, false, Type.getType(Object), []);
			var op:Instructions = Instructions.instance;
			
			var instructions : Array = [
				[op.GetLocal_0],
				[op.PushScope],
				
				[op.GetLocal_0],
				[op.GetSuper, property.qname],
				
				[op.GetLex, property.type.qname],
				[op.AsTypeLate],
				
				[op.ReturnValue]
			];
			
			return new DynamicMethod(method, 3, 2, 4, 5, instructions);
		}
		
		private function generateSuperPropertySetterMethod(property : PropertyInfo) : DynamicMethod
		{
			var valueParam : ParameterInfo = new ParameterInfo("value", property.type, false);
			var method : MethodInfo = new MethodInfo(property.owner, "set_" + property.name + "_internal", null, MemberVisibility.PRIVATE, false, false, Type.getType(Object), [valueParam]); 
			var op:Instructions = Instructions.instance;
			
			var instructions : Array = [
				[op.GetLocal_0],
				[op.PushScope],
				
				[op.GetLocal_0],
				[op.GetLocal_1],
				[op.SetSuper, property.qname],
				
				[op.ReturnVoid]
			];
			
			return new DynamicMethod(method, 4, 3, 4, 5, instructions);
		}
		
		private function generateCreateInstanceMethod(dynamicClass : DynamicClass) : DynamicMethod
		{
			var argCount : int = dynamicClass.constructor.parameters.length;
			var method : MethodInfo = new MethodInfo(dynamicClass, CREATE_METHOD, null, MemberVisibility.PUBLIC, true, false, dynamicClass, dynamicClass.constructor.parameters); 
			var op:Instructions = Instructions.instance;
			
			var instructions : Array = [
				[ op.GetLocal_0 ],
				[ op.PushScope ],
				
				[ op.GetLex, dynamicClass.qname ]
			];
				
			for (var i : int = 0; i<argCount; i++)
			{
				instructions.push(
					[ op.GetLocal, i + 1 ]
				);
			}
			
			instructions.push(
				[ op.Construct, dynamicClass.constructor.parameters.length ],
				[ op.ReturnValue ]
			);
			
			return new DynamicMethod(method, 2 + argCount, 2 + argCount, 3, 4, instructions);
		}
		
		private static const PROXY_FIELD_NAME : String = "__proxy__";
	}
}