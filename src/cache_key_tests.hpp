#pragma once

#pragma once

#include <catch.hpp>

#include "cache_key.hpp"

extern const char *TAG;

TEST_CASE( "cache::body_cache_key", TAG )
{
    SECTION( "complete" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "request": "l_sql", "params": { "list_path": ["pepelats"], "sql": ["dbl", "SELECT id, name, ddate FROM test_rmd WHERE id = ? OR id = ? ORDER BY id DESC", "ref.t1", 3], "t1": "ref.data.request.param.foo", "param2": "ref.data.request.baz", "cache_salt": "ref.data.cache_salt" } } })");
        auto data = nlohmann::json::parse(R"({ "request": { "baz": 6, "param": { "foo": 2 }, "Lib": 100 }, "other": { "data": "may be here" }, "user": { "id": 128 }, "cache_salt": 1 })");
        REQUIRE( machine::cache::body_cache_key(object, data, "") == "body:5d38e805abc0f69151169d9ec1dc605f" );
    }

    SECTION( "has cache_key" )
    {
        auto object = nlohmann::json::parse(R"({ "body": { "cache_key": "body:52d03f338ab1de21ef4d22553abe060a" } })");
        REQUIRE( machine::cache::body_cache_key(object, nlohmann::json::object(), "") == "body:52d03f338ab1de21ef4d22553abe060a" );
    }
}
