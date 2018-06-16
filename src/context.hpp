#pragma once

#include <memory>
#include <fstream>

#include <json.hpp>

#include "sql.hpp"
#include "cache.hpp"

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

		if (settings_.find("cache") != settings_.end())
		{
			cache_.reset(new cache::DefaultCache(settings_));
		}
		else
		{
			cache_.reset(new cache::NullCache());
		}
	}

	const nlohmann::json &settings() const
	{
		return settings_;
	}

	machine::sql::Database *database()
	{
		return database_.get();
	}

	cache::Cache *cache()
	{
		return cache_.get();
	}

private:
	Context() = default;

	nlohmann::json settings_;
	std::unique_ptr<machine::sql::Database> database_;
	std::unique_ptr<cache::Cache> cache_;
};

}
