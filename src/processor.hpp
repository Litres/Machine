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

#include "common.hpp"
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
		if (type.empty() || name.empty())
		{
			throw std::exception();
		}

		return Request(type, name);
	}
};

std::string merge(const std::vector<Result> &results)
{
	auto console = spdlog::get("console");

	json object = json::object();
	json::const_pointer parent = nullptr;
	for (auto &e : results)
	{
		console->debug("merge result object: {0}", e.data.dump());

		const json &list = e.data["result"]["list"];

		if (list.find("parent") != list.end())
		{
			parent = &e.data;
		}

		const json &hash = list["hash_by_id"];
		for (json::const_iterator i = hash.begin(); i != hash.end(); i++)
		{
			auto p = object.find(i.key());
			if (p == object.end())
			{
				object[i.key()] = i.value();
			}
			else
			{
				merge(i.value(), *p);
			}
		}
	}

	if (parent != nullptr)
	{
		const json &list = (*parent)["result"]["list"];

		// apply order
		const json &order = list["ordered_list"];
		json array = json::array();
		for (auto &i : order)
		{
			auto p = object.find(i["id"].get<std::string>());
			if (p == object.end())
			{
				throw std::logic_error("id not found");
			}
			else
			{
				array.push_back(*p);
			}
		}

		// path
		auto path = list.find("path");
		if (path == list.end())
		{
			json list = json::object();
			list["hash_by_id"] = array;

			json result = json::object();
			result["list"] = list;

			return result.dump();
		}

		json result = json::object();
		if (path->is_array())
		{
			json::pointer p = &result;
			for (size_t j = 0; j < path->size() - 1; j++)
			{
				json &current = *p;
				std::string key = (*path)[j];
				current[key] = json::object();
				p = &(current[key]);
			}
			json &current = *p;
			current[path->back().get<std::string>()] = array;
		}

		if (path->is_string())
		{
			result[path->get<std::string>()] = array;
		}

		return result.dump();
	}

	json list = json::object();
	list["hash_by_id"] = object;

	json result = json::object();
	result["list"] = list;

	return result.dump();
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

			auto result = merge(results_.items());
			console->debug("result: {0}", result);

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
	}

	std::shared_ptr<Function> create(const json &object)
	{
		const json &body = object["body"];
		const Request request = Request::create(body["request"]);
		if (request.name_ == "sql")
		{
			if (request.type_ == "l")
			{
				return std::make_shared<sql::ParentSQLFunction<Context>>(object, results_);
			}

			if (request.type_ == "h")
			{
				return std::make_shared<sql::ChildSQLFunction<Context>>(object, results_);
			}
		}
		
		throw std::exception();
	}

	tbb::flow::graph g_;
	std::vector<std::shared_ptr<Node>> nodes_;
	Queue results_;
};

}
