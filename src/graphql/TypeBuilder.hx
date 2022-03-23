package graphql;

import haxe.macro.Type.ClassType;
import haxe.macro.Context;
import haxe.macro.Expr;
import graphql.GraphQLField;

using StringTools;
using graphql.TypeBuilder;
using haxe.macro.TypeTools;

class TypeBuilder {
	/**
		Automatically build the GraphQL type definition based on the class
	**/
	macro static public function build():Array<Field> {
		var fields = Context.getBuildFields();
		buildClass(fields);
		return fields;
	}

	#if macro
	static function buildClass(fields:Array<Field>) {
		var graphql_field_definitions:Array<ExprOf<GraphQLField>> = [];
		var graphql_mutation_field_definitions:Array<ExprOf<GraphQLField>> = [];
		for (f in fields) {
			var new_field = buildFieldType(f);
			if (new_field != null) {
				graphql_field_definitions.push(new_field);
			}
			var new_field = buildFieldType(f, Mutation);
			if (new_field != null) {
				graphql_mutation_field_definitions.push(new_field);
			}
		}

		var cls = Context.getLocalClass().get();
		
		var type_name : ExprOf<String> = cls.classHasMeta(TypeName) ? cls.classGetMeta(TypeName).params[0] : macro $v{cls.name};
		var mutation_name : ExprOf<String> = cls.classHasMeta(MutationTypeName) ? cls.classGetMeta(MutationTypeName).params[0] : macro $v{cls.name + "Mutation"};

		var tmp_class = macro class {
			/**
				Auto-generated list of public fields on the class. Prototype for generating a full graphql definition
			**/
			public static var _gql : graphql.TypeObjectDefinition = {
				 fields: $a{graphql_field_definitions},
				 mutation_fields: $a{graphql_mutation_field_definitions},
				 type_name: $type_name,
				 mutation_name: $mutation_name,
				 description: $v{ cls.doc != null ? cls.doc.trim() : null  }
			};

			override public function get_gql() : graphql.TypeObjectDefinition {
				return _gql;
			};
		}

		for (field in tmp_class.fields) {
			fields.push(field);
		}
	}

	static function classHasMeta(cls : ClassType, name : FieldMetadata) {
		var found = false;
		for (meta in cls.meta.get()) {
			if ([':$name', name].contains(meta.name)) {
				if(found == true) {
					throw new Error('Duplicate metadata found for $name on ${cls.name}', meta.pos);
				}
				found = true;
			}
		}
		return found;
	}


	/**
		Retrieves list of metadata with the given name (with or without preceding `:`)
	**/
	static function classGetMetas(cls : ClassType, name : FieldMetadata) {
		return cls.meta.get().filter((meta) -> {
			return [':$name', name].contains(meta.name);
		});
	}

	/**
		Retrieves the *first* metadata item with the provided name (with or without preceding `:`)
	**/
	static function classGetMeta(cls: ClassType, name : FieldMetadata) {
		return classGetMetas(cls, name)[0];
	}

	static function buildFieldType(f:Field, type: GraphQLObjectType = Query):ExprOf<GraphQLField> {
		var cls = Context.getLocalClass().get();
		var field = new FieldTypeBuilder(f, type);

		if (field.isVisible()) {

			var classValidationContext : Array<Expr> = [];
			if (classHasMeta(cls, ClassValidationContext)) {
				var validations = classGetMetas(cls, ClassValidationContext);
				for(v in validations) {
					var expr = v.params[0];
					classValidationContext.push(expr);
				}
			}

			var type = field.getType();
			var comment = field.getComment();
			var deprecationReason = field.getDeprecationReason();
			var validations = field.getValidators();
			var postValidations = field.getValidators(ValidateAfter);
			var validationContext = field.getValidationContext();
			var ctx_var_name = field.getContextVariableName();

			var number_of_validations = validations.length;
			var number_of_post_validations = postValidations.length;

			var joined_arguments = [for(f in field.arg_names) f == ctx_var_name ? macro ctx : macro args.$f ];
			var arg_var_defs = [for(f in field.arg_names) f == ctx_var_name ? macro var $f = ctx : macro var $f = args.$f ];
			validations = classValidationContext.concat(arg_var_defs).concat(validationContext).concat(validations);
			postValidations = classValidationContext.concat(arg_var_defs).concat(validationContext).concat(postValidations);
			var objectType = TPath({name: cls.name, params: [], pack: cls.pack});
			var name = f.name;

			var resolve = macro {};
			if (!field.is_function) {
				if(number_of_validations == 0 && number_of_post_validations == 0) {
					resolve = macro null;
				} else {
					resolve = macro (obj : $objectType, args : graphql.ArgumentAccessor, ctx) -> {
						$b{validations};
						var result = obj.$name;
						$b{postValidations};
						return result;
	
					}
				}
			} else {
				resolve = macro (obj : $objectType, args : graphql.ArgumentAccessor, ctx) -> {
					$b{validations};
					var result = php.Syntax.code('{0}(...{1})', obj.$name, $a{ joined_arguments });
					$b{postValidations};
					return result;

				}
			}


			var field:ExprOf<GraphQLField> = macro {
				name: $v{f.name},
				type: $type,
				description: $v{comment},
				deprecationReason: $deprecationReason,
				args: php.Lib.toPhpArray( ${ field.args } ),
				resolve: $resolve
			}
			return field;
		}
		return null;
	}
	#end
}
