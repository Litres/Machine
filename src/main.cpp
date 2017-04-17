#include <iostream>

#include <spdlog/spdlog.h>

#include "context.hpp"
#include "server.hpp"

int main(int argc, char* argv[])
{
	if (argc != 2)
	{
		std::cout << "Usage: Machine <port>" << std::endl;
		return 1;
	}

	spdlog::set_pattern("[%H:%M:%S] [t %t] %l: %v");
	spdlog::set_level(spdlog::level::debug);
	auto console = spdlog::stdout_logger_mt("console");
	
	auto port = std::atoi(argv[1]);
	console->info("starting Machine at port {:d}", port);
	try
	{
		machine::Context::instance().setup();
		machine::start(port);
		return 0;
	}
	catch (const std::exception &e)
	{
		console->error(e.what());
		return 1;
	}
}
