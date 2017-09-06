#define CATCH_CONFIG_MAIN  // This tells Catch to provide a main() - only do this in one cpp file

#include <string>

#include <catch.hpp>
#include <json.hpp>

#include "sql.hpp"

const char *TAG = "[Machine]";

TEST_CASE( "sql::travel", TAG )
{
	SECTION( "travel object" )
	{
		auto object = nlohmann::json::parse("{ \"one\": { \"two\": { \"three\": [] } } }");
		const nlohmann::json &result = machine::sql::travel(object, "one");
		REQUIRE( result.is_object() );
	}

	SECTION( "travel array" )
	{
		auto object = nlohmann::json::parse("{ \"one\": { \"two\": { \"three\": [] } } }");
		const nlohmann::json &result = machine::sql::travel(object, "one.two.three");
		REQUIRE( result.is_array() );
	}
}

TEST_CASE( "sql::Query", TAG )
{
	SECTION( "no parameters" )
	{
		auto object = nlohmann::json::parse("{ \"body\": { \"params\": { \"sql\": [ \"dbh\", \"SELECT id FROM user\" ] } } }");
		machine::sql::Query query(object);
		REQUIRE( query.alias() == "dbh" );
		REQUIRE( query.sql() == "SELECT id FROM user" );
	}

	SECTION( "value parameter" )
	{
		auto object = nlohmann::json::parse("{ \"body\": { \"params\": { \"sql\": [ \"dbh\", \"SELECT id, name FROM user WHERE id = ?\", 1 ] } } }");
		machine::sql::Query query(object);
		REQUIRE( query.alias() == "dbh" );
		REQUIRE( query.sql() == "SELECT id, name FROM user WHERE id = 1" );
	}

	SECTION( "reference parameter" )
	{
		auto object = nlohmann::json::parse("{ \"body\": { \"params\": { \"sql\": [ \"dbh\", \"SELECT id, name FROM user WHERE id = ?\", \"ref.id\" ], \"id\": 1 } } }");
		machine::sql::Query query(object);
		REQUIRE( query.alias() == "dbh" );
		REQUIRE( query.sql() == "SELECT id, name FROM user WHERE id = 1" );
	}

	SECTION( "global reference parameter" )
	{
		auto object = nlohmann::json::parse("{ \"body\": { \"params\": { \"sql\": [ \"dbh\", \"SELECT id, name FROM user WHERE id = ?\", \"ref.id\" ], \"id\": \"ref.data.request.id\" } }, \"data\": { \"request\": { \"id\": 1 } } }");
		machine::sql::Query query(object);
		REQUIRE( query.alias() == "dbh" );
		REQUIRE( query.sql() == "SELECT id, name FROM user WHERE id = 1" );
	}

	SECTION( "two parameters" )
	{
		auto object = nlohmann::json::parse("{ \"body\": { \"params\": { \"sql\": [ \"dbh\", \"SELECT id, name, age FROM user WHERE id = ? AND age > ?\", 1, 25 ] } } }");
		machine::sql::Query query(object);
		REQUIRE( query.alias() == "dbh" );
		REQUIRE( query.sql() == "SELECT id, name, age FROM user WHERE id = 1 AND age > 25" );
	}

	SECTION( "named placeholder" )
	{
		auto object = nlohmann::json::parse("{ \"body\": { \"params\": { \"sql\": [ \"dbh\", \"SELECT id, name, age FROM user WHERE id = ? AND age > :age\", 1, { \":age\": 25 } ] } } }");
		machine::sql::Query query(object);
		REQUIRE( query.alias() == "dbh" );
		REQUIRE( query.sql() == "SELECT id, name, age FROM user WHERE id = 1 AND age > 25" );
	}

	SECTION( "another" )
	{
		auto object = nlohmann::json::parse("{ \"data\": { \"request\": { \"baz\": 6, \"param\": { \"foo\": 1 }, \"Lib\": 100 }, \"other\" : { \"data\": \"may be here\" } }, \"body\": { \"params\": { \"sql\": [\"dbl\", \"SELECT id, name, ddate FROM test_rmd WHERE id = ? OR id BETWEEN ? AND :bar ORDER BY id DESC\", \"ref.t1\", { \":bar\": \"ref.param2\" }, 3], \"t1\": \"ref.data.request.param.foo\", \"list_path\": [\"путь\", \"для\", \"сохранения\", \"списка\"], \"param2\": \"ref.data.request.baz\" }, \"request\": \"l_sql\" } }");
		machine::sql::Query query(object);
		REQUIRE( query.alias() == "dbl" );
		REQUIRE( query.sql() == "SELECT id, name, ddate FROM test_rmd WHERE id = 1 OR id BETWEEN 3 AND 6 ORDER BY id DESC" );
	}
}
