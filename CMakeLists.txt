cmake_minimum_required (VERSION 2.8)
add_compile_options (-std=c++14)
project (Machine)

set (CMAKE_BUILD_TYPE Debug)

set (SOURCE_FILES
        src/log.hpp
        src/context.hpp
        src/function.hpp
        src/processor.hpp
        src/server.hpp
        src/db.hpp
        src/db_tests.hpp
        src/sql.hpp
        src/common.hpp
        src/hash.hpp
        src/hash_tests.hpp
        src/cache.hpp
        src/cache_key.hpp
        src/cache_key_tests.hpp
        src/perl.hpp
        src/main.cpp)

link_libraries (pthread memcached crypto++)

find_package (Boost COMPONENTS system REQUIRED)
include_directories (${Boost_INCLUDE_DIRS})

link_directories (lib/tbb/lib)
include_directories (lib/tbb/include)

link_directories (lib/mysql/lib)
include_directories (lib/mysql/include)

include_directories (lib/spdlog/include)
include_directories (lib/json/include)
include_directories (lib/catch/include)

include_directories (perl-bridge/include)
add_subdirectory (perl-bridge)

add_executable (Machine ${SOURCE_FILES})
target_link_libraries (Machine perl-bridge)
target_link_libraries (Machine ${Boost_SYSTEM_LIBRARY})
target_link_libraries (Machine tbb)
target_link_libraries (Machine mysqlcppconn)

add_executable (Test src/test.cpp)
