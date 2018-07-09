#pragma once

#include <string>

#include <catch.hpp>
#include <json.hpp>

#include "db.hpp"

extern const char *TAG;

TEST_CASE( "sql::travel", TAG )
{
    SECTION( "travel object" )
    {
        auto object = nlohmann::json::parse(R"({ "one": { "two": { "three": [] } } })");
        const nlohmann::json &result = machine::sql::travel(object, "one");
        REQUIRE( result.is_object() );
    }

    SECTION( "travel array" )
    {
        auto object = nlohmann::json::parse(R"({ "one": { "two": { "three": [] } } })");
        const nlohmann::json &result = machine::sql::travel(object, "one.two.three");
        REQUIRE( result.is_array() );
    }
}

TEST_CASE( "sql::Query", TAG )
{
    SECTION( "no parameters" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "params": { "sql": [ "dbh", "SELECT id FROM user" ] } } })");
        machine::sql::Query query(object, nlohmann::json::object());
        query.bind([](const std::string &value) { return value; });
        REQUIRE( query.alias() == "dbh" );
        REQUIRE( query.sql() == "SELECT id FROM user" );
    }

    SECTION( "value parameter" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "params": { "sql": [ "dbh", "SELECT id, name FROM user WHERE id = ?", 1 ] } } })");
        machine::sql::Query query(object, nlohmann::json::object());
        query.bind([](const std::string &value) { return value; });
        REQUIRE( query.alias() == "dbh" );
        REQUIRE( query.sql() == "SELECT id, name FROM user WHERE id = 1" );
    }

    SECTION( "reference parameter" )
    {
        auto object = nlohmann::json::parse(
                R"({ "body": { "params": { "sql": [ "dbh", "SELECT id, name FROM user WHERE id = ?", "ref.id" ], "id": 1 } } })");
        machine::sql::Query query(object, nlohmann::json::object());
        query.bind([](const std::string &value) { return value; });
        REQUIRE( query.alias() == "dbh" );
        REQUIRE( query.sql() == "SELECT id, name FROM user WHERE id = 1" );
    }

    SECTION( "global reference parameter" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "params": { "sql": [ "dbh", "SELECT id, name FROM user WHERE id = ?", "ref.id" ], "id": "ref.data.request.id" } } })");
        auto data = nlohmann::json::parse(R"({ "request": { "id": 1 } })");

        machine::sql::Query query(object, data);
        query.bind([](const std::string &value) { return value; });
        REQUIRE( query.alias() == "dbh" );
        REQUIRE( query.sql() == "SELECT id, name FROM user WHERE id = 1" );
    }

    SECTION( "two parameters" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "params": { "sql": [ "dbh", "SELECT id, name, age FROM user WHERE id = ? AND age > ?", 1, 25 ] } } })");
        machine::sql::Query query(object, nlohmann::json::object());
        query.bind([](const std::string &value) { return value; });
        REQUIRE( query.alias() == "dbh" );
        REQUIRE( query.sql() == "SELECT id, name, age FROM user WHERE id = 1 AND age > 25" );
    }

    SECTION( "named placeholder" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "params": { "sql": [ "dbh", "SELECT id, name, age FROM user WHERE id = ? AND age > :age", 1, { ":age": 25 } ] } } })");
        machine::sql::Query query(object, nlohmann::json::object());
        query.bind([](const std::string &value) { return value; });
        REQUIRE( query.alias() == "dbh" );
        REQUIRE( query.sql() == "SELECT id, name, age FROM user WHERE id = 1 AND age > 25" );
    }

    SECTION( "another" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "params": { "sql": ["dbl", "SELECT id, name, ddate FROM test_rmd WHERE id = ? OR id BETWEEN ? AND :bar ORDER BY id DESC", "ref.t1", { ":bar": "ref.param2" }, 3], "t1": "ref.data.request.param.foo", "list_path": ["путь", "для", "сохранения", "списка"], "param2": "ref.data.request.baz" }, "request": "l_sql" } })");
        auto data = nlohmann::json::parse(R"({ "request": { "baz": 6, "param": { "foo": 1 }, "Lib": 100 }, "other" : { "data": "may be here" } })");

        machine::sql::Query query(object, data);
        query.bind([](const std::string &value) { return value; });
        REQUIRE( query.alias() == "dbl" );
        REQUIRE( query.sql() == "SELECT id, name, ddate FROM test_rmd WHERE id = 1 OR id BETWEEN 3 AND 6 ORDER BY id DESC" );
    }

    SECTION( "area and user" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "params": { "sql": [ "dbh", "SELECT id FROM user" ] } } })");
        auto data = nlohmann::json::parse(R"({ "request": { "Lib": 100 }, "user": { "id": 6 } })");

        machine::sql::Query query(object, data);
        query.bind([](const std::string &value) { return value; });
        REQUIRE( query.area() == 100 );
        REQUIRE( query.user() == 6 );
    }
}

TEST_CASE( "sql::server", TAG )
{
    SECTION( "server" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "params": { "sql": [ "dbh", "SELECT id FROM user" ] } } })");
        machine::sql::Query query(object, nlohmann::json::object());

        auto parameters = nlohmann::json::parse(R"({ "server": "127.0.0.1:3306" })");
        REQUIRE( machine::sql::make_server(query, parameters) == "127.0.0.1:3306" );
    }

    SECTION( "shards" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "params": { "sql": [ "dbh", "SELECT id FROM user" ] } } })");
        auto data = nlohmann::json::parse(R"({ "user": { "id": 2 } })");
        machine::sql::Query query(object, data);

        auto parameters = nlohmann::json::parse(R"({ "shards": ["127.0.0.1:3306", "db.test_1:3306", "db.test_2:3306"] })");
        REQUIRE( machine::sql::make_server(query, parameters) == "db.test_2:3306" );
    }
}

TEST_CASE( "sql::schema", TAG )
{
    SECTION( "value" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "params": { "sql": [ "dbh", "SELECT id FROM user" ] } } })");
        machine::sql::Query query(object, nlohmann::json::object());

        auto parameters = nlohmann::json::parse(R"({ "schema": "test" })");
        REQUIRE( machine::sql::make_schema(query, parameters) == "test" );
    }

    SECTION( "template" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "params": { "sql": [ "dbh", "SELECT id FROM user" ] } } })");
        auto data = nlohmann::json::parse(R"({ "request": { "Lib": 100 } })");
        machine::sql::Query query(object, data);

        auto parameters = nlohmann::json::parse(R"({ "schema_template": "lib_area_%d" })");
        REQUIRE( machine::sql::make_schema(query, parameters) == "lib_area_100" );
    }
}

TEST_CASE( "sql::keep", TAG )
{
    SECTION( "no" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "params": { "sql": [ "dbh", "SELECT id FROM user" ] } } })");
        auto data = nlohmann::json::parse(R"({ "request": { "Lib": 1 } })");
        machine::sql::Query query(object, data);

        auto parameters = nlohmann::json::parse(R"({ "keep_connect": [2] })");
        REQUIRE( !machine::sql::keep_connection(query, parameters) );
    }

    SECTION( "yes" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "params": { "sql": [ "dbh", "SELECT id FROM user" ] } } })");
        auto data = nlohmann::json::parse(R"({ "request": { "Lib": 2 } })");
        machine::sql::Query query(object, data);

        auto parameters = nlohmann::json::parse(R"({ "keep_connect": [1, 2] })");
        REQUIRE( machine::sql::keep_connection(query, parameters) );
    }
}
