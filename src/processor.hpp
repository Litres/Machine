#pragma once

#include <vector>
#include <string>
#include <memory>
#include <exception>
#include <thread>

#include <spdlog/spdlog.h>
#include <json.hpp>

#include <tbb/tbb.h>
#include <tbb/flow_graph.h>

#include "context.hpp"
#include "sql.hpp"

namespace machine
{

using json = nlohmann::json;
using Node = tbb::flow::function_node<json, json>;

struct Request
{
	std::string type_;
	std::string name_;

	Request(const std::string &type, const std::string &name) : type_(type), name_(name) {}

	static Request create(const std::string &value)
	{
		auto p = std::find(value.begin(), value.end(), '_');
		if (p == value.end())
		{
			throw std::exception();
		}

		std::string type(value.begin(), p);
		std::string name(p + 1, value.end());
		if (type.size() == 0 || name.size() == 0)
		{
			throw std::exception();
		}

		return Request(type, name);
	}
};

struct Result
{
	json data;

	Result(const json &data) : data(data) {}
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

struct ResultFunction : public Function
{
	Queue &results_;

	ResultFunction(const json &object, Queue &results) : Function(object), results_(results) {}

	json execute(const json &v) const override
	{
		auto console = spdlog::get("console");
		console->debug("result: {0}", v.dump());
		results_.push(Result(v));
		return json();
	}
};

void merge(const json &from, json &to)
{
	for (json::const_iterator j = from.begin(); j != from.end(); j++)
	{
		if (to.find(j.key()) == to.end())
		{
			to[j.key()] = j.value();
		}
	}
}

json merge(const std::vector<Result> &results)
{
	json result = json::object();
	for (auto &e : results)
	{
		const json &hash = e.data["result"]["list"]["hash_by_id"];
		for (json::const_iterator i = hash.begin(); i != hash.end(); i++)
		{
			auto p = result.find(i.key());
			if (p == result.end())
			{
				result[i.key()] = i.value();
			}
			else
			{
				merge(i.value(), *p);
			}
		}
	}
	return result;
}

class Processor
{
public:
	std::string process(const std::string &request)
	{
		auto console = spdlog::get("console");
		console->debug("request: {0}", request);

		try
		{
			const json object = json::parse(request);
			add(nullptr, object);

			nodes_[0]->try_put(object["data"]);
			g_.wait_for_all();

			json result = merge(results_.items());
			console->debug("result: {0}", result.dump());

			return result;
		}
		catch (const std::exception &e)
		{
			console->error(e.what());
			return std::string();
		}
	}

private:
	void add(std::shared_ptr<Node> parent, const json &object)
	{
		std::shared_ptr<Node> node(new Node(g_, 1, FunctionBridge(create(object))));
		nodes_.push_back(node);

		if (parent)
		{
			tbb::flow::make_edge(*parent, *node);
		}

		auto i = object.find("childs");
		if (i != object.end())
		{
			const json &children = *i;
			if (!children.is_array())
			{
				throw std::exception();
			}

			for (const json &e : children)
			{
				add(node, e);
			}
		}
		else
		{
			std::shared_ptr<Node> child(new Node(g_, 1, FunctionBridge(std::make_shared<ResultFunction>(object, results_))));
			nodes_.push_back(child);
			tbb::flow::make_edge(*node, *child);
		}
	}

	std::shared_ptr<Function> create(const json &object)
	{
		const json &body = object["body"];
		const Request request = Request::create(body["request"]);
		if (request.name_ == "sql")
		{
			if (request.type_ == "l")
			{
				return std::make_shared<sql::ParentSQLFunction<Context>>(object);
			}

			if (request.type_ == "h")
			{
				return std::make_shared<sql::ChildSQLFunction<Context>>(object);
			}
		}
		
		throw std::exception();
	}

	tbb::flow::graph g_;
	std::vector<std::shared_ptr<Node>> nodes_;
	Queue results_;
};

}
