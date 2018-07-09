#include <iostream>

#include "log.hpp"
#include "context.hpp"
#include "server.hpp"

int main(int argc, char* argv[])
{
	if (argc != 2)
	{
		std::cout << "Usage: Machine <port>" << std::endl;
		return 1;
	}

	logger::setup();
	
	auto port = std::atoi(argv[1]);
	logger::get()->info("starting Machine at port {:d}", port);
	try
	{
		machine::Context::instance().setup();
		machine::start(port);
		return 0;
	}
	catch (const std::exception &e)
	{
		logger::get()->error(e.what());
		return 1;
	}
}
