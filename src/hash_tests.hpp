#pragma once

#include <catch.hpp>

#include "hash.hpp"

extern const char *TAG;

TEST_CASE( "machine::HashBuilder", TAG )
{
    SECTION( "" )
    {
        machine::HashBuilder builder;
        builder.update("test");
        REQUIRE( builder.final() == "098f6bcd4621d373cade4e832627b4f6" );
    }
}
