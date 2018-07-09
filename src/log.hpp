#pragma once

#include <spdlog/spdlog.h>

namespace logger
{

void setup()
{
	spdlog::set_pattern("[%H:%M:%S] [t %t] %l: %v");
	spdlog::set_level(spdlog::level::debug);
	auto console = spdlog::stdout_logger_mt("console");
	console->debug("logger ready");
}

std::shared_ptr<spdlog::logger> get()
{
	return spdlog::get("console");
}
    
}
