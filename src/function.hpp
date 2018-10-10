#pragma once

#include <set>

#include <json.hpp>

#include "log.hpp"

namespace machine
{

using json = nlohmann::json;

struct Result
{
	json data;
	size_t level;

	explicit Result(size_t level, const json &data) : level(level), data(data) {}
};

struct ResultComparator
{
	bool operator()(const Result& a, const Result& b)
	{
		return a.level < b.level;
	}
};

struct Queue
{
	typedef std::multiset<Result, ResultComparator> ResultSet;

	void push(const Result &result)
	{
		std::lock_guard<std::mutex> lock(mutex_);
		items_.insert(result);
	}

	const ResultSet &items() const
	{
		return items_;
	}

private:
	ResultSet items_;
	std::mutex mutex_;
};

struct Function
{
	const size_t level_;
	const bool use_cache_;
	const json &object_;
	Queue &results_;

	Function(size_t level, bool use_cache, const json &object, Queue &results) : level_(level), 
		use_cache_(use_cache), object_(object), results_(results) {}

	virtual json execute(const json &v) const = 0;

};

class FunctionBridge
{
public:
	explicit FunctionBridge(std::shared_ptr<Function> f) : f_(f) {}

	json operator()(json v) const
	{
		logger::get()->debug("function object: {0}", f_->object_.dump());
		return f_->execute(v);
	}

private:
	std::shared_ptr<Function> f_;
};

}
