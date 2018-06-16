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

		database_.reset(new machine::sql::DefaultDatabase(settings_));
	}

	const nlohmann::json &settings() const
	{
		return settings_;
	}

	machine::sql::Database *database()
	{
		return database_.get();
	}

private:
	Context() = default;

	nlohmann::json settings_;
	std::unique_ptr<machine::sql::Database> database_;
};

}
