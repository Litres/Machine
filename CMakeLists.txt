cmake_minimum_required (VERSION 2.8)
add_compile_options (-std=c++11)
project (Machine)

link_libraries (pthread)

find_package (Boost COMPONENTS system REQUIRED)
include_directories (${Boost_INCLUDE_DIRS})

link_directories (lib/tbb/lib)
include_directories (lib/tbb/include)

link_directories (lib/mysql/lib)
include_directories (lib/mysql/include)

include_directories (lib/spdlog/include)
include_directories (lib/json/include)
include_directories (lib/catch/include)

add_executable (Machine src/main.cpp)
target_link_libraries (Machine ${Boost_SYSTEM_LIBRARY})
target_link_libraries (Machine tbb)
target_link_libraries (Machine mysqlcppconn)

add_executable (Test src/test.cpp)
