#pragma once

#include <spdlog/spdlog.h>
#include <json.hpp>

namespace machine
{

using json = nlohmann::json;

struct Result
{
	json data;

	explicit Result(const json &data) : data(data) {}
};

struct Queue
{
	void push(const Result &result)
	{
		std::lock_guard<std::mutex> lock(mutex_);
		items_.push_back(result);
	}

	const std::vector<Result> &items() const
	{
		return items_;
	}

private:
	std::vector<Result> items_;
	std::mutex mutex_;
};

struct Function
{
	const json &object_;
	Queue &results_;

	Function(const json &object, Queue &results) : object_(object), results_(results) {}

	virtual json execute(const json &v) const = 0;

};

class FunctionBridge
{
public:
	explicit FunctionBridge(std::shared_ptr<Function> f) : f_(f) {}

	json operator()(json v) const
	{
		auto console = spdlog::get("console");
		console->debug("function object: {0}", f_->object_.dump());
        return f_->execute(v);
	}

private:
	std::shared_ptr<Function> f_;
};

}
