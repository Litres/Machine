#pragma once

#include <spdlog/spdlog.h>
#include <json.hpp>

namespace machine
{

using json = nlohmann::json;

struct Function
{
	const json &object_;

	Function(const json &object) : object_(object) {}

	virtual json execute(const json &v) const = 0;

};

class FunctionBridge
{
public:
	FunctionBridge(std::shared_ptr<Function> f) : f_(f) {}

	json operator()(json v) const
	{
		auto console = spdlog::get("console");
		console->debug("function object: {0}", f_->object_.dump());
		try
		{
			return f_->execute(v);
		}
		catch (const std::exception &e)
		{
			console->error(e.what());
			return json::object();
		}
	}

private:
	std::shared_ptr<Function> f_;
};

}
