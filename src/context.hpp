#pragma once

#include <memory>
#include <fstream>

#include <json.hpp>

#include "sql.hpp"

namespace machine
{

class Context
{
public:
	static Context &instance()
	{
		static Context context;
		return context;
	}

	void setup()
	{
		std::ifstream file("settings.json");
		file >> settings_;

		pool_ = std::make_shared<machine::sql::Pool<Context>>();
	}

	const nlohmann::json &settings() const
	{
		return settings_;
	}

	std::shared_ptr<machine::sql::Pool<Context>> pool()
	{
		return pool_;
	}

private:
	Context() {}

	nlohmann::json settings_;
	std::shared_ptr<machine::sql::Pool<Context>> pool_;
};

}