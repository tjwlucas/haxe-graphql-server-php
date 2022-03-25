package graphql.externs;

import graphql.externs.NativeArray;

@:native('GraphQL\\GraphQL')
extern class GraphQL {
    public static function executeQuery(schema: Schema, query: String, rootValue : Dynamic, ?contextValue : Dynamic, ?variables: NativeArray, ?operationName:String) : ExecutionResult;
}