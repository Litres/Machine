#pragma once

#include <memory>
#include <mutex>
#include <unordered_map>
#include <algorithm>

#include <json.hpp>

#include <boost/lexical_cast.hpp>
#include <boost/algorithm/string.hpp>
#include <boost/format.hpp>

#include <mysql_connection.h>
#include <cppconn/driver.h>
#include <cppconn/exception.h>
#include <cppconn/resultset.h>
#include <cppconn/statement.h>

#include "log.hpp"
#include "common.hpp"

namespace machine
{
namespace sql
{

using json = nlohmann::json;

class Query
{
public:
	Query(const json &object, const json &data) : last_(0), area_(-1), user_(-1)
	{
		const json &body = object["body"];
		const json &parameters = body["params"];
		const json &sql = parameters["sql"];
		if (!sql.is_array() || sql.size() < 2)
		{
			throw std::invalid_argument(sql.dump());
		}

		auto i = sql.begin();
		alias_ = *i++;
		sql_ = *i++;

		Resolver r1(parameters);
		Resolver r2(json::object({ {"data", data} }));

		while (i != sql.end())
		{
			const json &e = *i++;
			if (e.is_number())
			{
				place(boost::lexical_cast<std::string>(e.get<double>()));
			}

			if (e.is_string())
			{
				const std::string &parameter = e.get<std::string>();
				std::string value = r2.resolve(r1.resolve(parameter));
				place(value);
			}

			if (e.is_object())
			{
				for (json::const_iterator i = e.begin(); i != e.end(); i++)
				{
					const json &value = i.value();
					if (value.is_number())
					{
						boost::replace_all(sql_, i.key(), boost::lexical_cast<std::string>(value.get<double>()));
					}

					if (value.is_string())
					{
						const std::string &parameter = value.get<std::string>();
						std::string value = r2.resolve(r1.resolve(parameter));
						place(i.key(), value);
					}
					
				}
			}
		}

		// TODO another way?
		auto p1 = find(data, "request.Lib");
		if (p1 != nullptr)
		{
			area_ = (*p1).get<long>();
		}

		auto p2 = find(data, "user.id");
		if (p2 != nullptr)
		{
			user_ = (*p2).get<long>();
		}
	}

	void place(const std::string &name, const std::string &value)
	{
		named_[name] = value;
	}

	void bind(std::function<std::string (const std::string &)> f)
	{
		auto t = [f](const std::string &value) {
			const char *start = value.c_str();
			char *end = nullptr;
			if (std::strtod(start, &end) == 0 && end == start)
			{
				return '\'' + f(value) + '\'';
			}
			else
			{
				return value;
			}
		};

		for (auto &value : unnamed_)
		{
			auto p = sql_.find('?', last_);
			if (p == std::string::npos)
			{
				throw std::logic_error(value);
			}
			sql_.replace(p, 1, t(value));
			last_ = p + 1;
		}

		for (auto &pair : named_)
		{
			boost::replace_all(sql_, pair.first, t(pair.second));
		}
	}

	const std::string &alias() const
	{
		return alias_;
	}

	const std::string &sql() const
	{
		return sql_;
	}

	long area() const
	{
		return area_;
	}

	long user() const
	{
		return user_;
	}

private:
	void place(const std::string &value)
	{
		unnamed_.push_back(value);
	}

	std::string alias_;
	std::string sql_;
	std::string::size_type last_;

	std::vector<std::string> unnamed_;
	std::map<std::string, std::string> named_;

	long area_;
	long user_;
};

std::string make_server(const Query &query, const json &parameters)
{
	auto p1 = parameters.find("server");
	if (p1 != parameters.end())
	{
		return *p1;
	}

	auto p2 = parameters["shards"];
	if (query.user() == -1)
	{
		throw std::logic_error("user id expected");
	}

	return p2[query.user() % p2.size()].get<std::string>();
}

std::string make_schema(const Query &query, const json &parameters)
{
	auto p1 = parameters.find("schema");
	if (p1 != parameters.end())
	{
		return *p1;
	}

	auto p2 = parameters["schema_template"];
	if (query.area() == -1)
	{
		throw std::logic_error("area expected");
	}

	return (boost::format(p2.get<std::string>()) % query.area()).str();
}

bool keep_connection(const Query &query, const json &parameters)
{
	auto p = parameters.find("keep_connect");
	if (p != parameters.end())
	{
		auto array = *p;
		if (std::find(array.begin(), array.end(), query.area()) != array.end())
		{
			return true;
		}
	}
	return false;
}

json convert(std::unique_ptr<::sql::ResultSet> &set, unsigned int i)
{
	switch (set->getMetaData()->getColumnType(i))
	{
		case ::sql::DataType::BIT:
		case ::sql::DataType::TINYINT:
		case ::sql::DataType::SMALLINT:
		case ::sql::DataType::MEDIUMINT:
		case ::sql::DataType::INTEGER:
		case ::sql::DataType::BIGINT:
			return set->getInt64(i);

		case ::sql::DataType::REAL:
		case ::sql::DataType::DOUBLE:
			return set->getDouble(i);

		default:
			return set->getString(i);
	}
}

json convert(std::unique_ptr<::sql::ResultSet> &set)
{
	json row = json::object();
	for (unsigned int i = 1; i <= set->getMetaData()->getColumnCount(); i++)
	{
		if (set->isNull(i))
		{
			continue;
		}

		std::string key = set->getMetaData()->getColumnLabel(i);
		row[key] = convert(set, i);
	}
	return row;
}

class Database
{
public:
	virtual std::vector<json> execute(Query &query) = 0;

protected:
	Database() = default;
};

class DefaultDatabase : public Database
{
public:
	explicit DefaultDatabase(const json &settings) : settings_(settings), last_id_(0) {}

	std::vector<json> execute(Query &query) override
	{
		std::unique_ptr<Guard> guard(create(query));
		std::unique_ptr<::sql::Statement> statement(guard->get()->createStatement());

		query.bind([&guard](const std::string &value) {
			auto p = dynamic_cast<::sql::mysql::MySQL_Connection *>(guard->get());
			return p->escapeString(value);
		});

		logger::get()->debug("executing SQL query: {0}", query.sql());
		std::unique_ptr<::sql::ResultSet> set(statement->executeQuery(query.sql()));

		std::vector<json> result;
		while (set->next())
		{
			result.emplace_back(convert(set));
		}
		return result;
	}

private:
	struct Pointer
	{
		explicit Pointer(::sql::Connection *connection, int id) : connection(connection), id(id), free(true) {}

		~Pointer()
		{
			delete connection;
		}

		::sql::Connection *connection;
		int id;
		bool free;
	};

	typedef std::unique_ptr<Pointer> UniquePointer;
	typedef std::vector<UniquePointer> PointerVector;
	typedef std::unordered_map<std::string, PointerVector> Pool;

	class Guard
	{
	public:
		explicit Guard(Pointer *pointer) : pointer_(pointer) {}

		::sql::Connection *get() const
		{
			return pointer_->connection;
		}

		virtual ~Guard() = default;

	protected:
		Pointer *pointer_;
	};

	class FreeGuard : public Guard
	{
	public:
		explicit FreeGuard(Pointer *pointer) : Guard(pointer) {}

		~FreeGuard() override
		{
			delete Guard::pointer_;
		}
	};

	class ReleaseGuard : public Guard
	{
	public:
		explicit ReleaseGuard(Pointer *pointer) : Guard(pointer) {}

		~ReleaseGuard() override
		{
			Guard::pointer_->free = true;
		}
	};

	Guard *create(const Query &query)
	{
		const json &parameters = settings_["db"][query.alias()];
		if (keep_connection(query, parameters))
		{
			return get(query);
		}

		const std::string &username = parameters["username"];
		const std::string &password = parameters["password"];

		auto driver = get_driver_instance();
		auto pointer = new Pointer(driver->connect("tcp://" + make_server(query, parameters), username, password), 0);
		pointer->connection->setSchema(make_schema(query, parameters));

		return new FreeGuard(pointer);
	}

	ReleaseGuard *get(const Query &query)
	{
		const json &parameters = settings_["db"][query.alias()];
		const std::string server = make_server(query, parameters);
		const std::string schema = make_schema(query, parameters);

		std::lock_guard<std::mutex> guard(mutex_);

		const std::string key = server + ":" + schema;
		auto p1 = pool_.find(key);
		if (p1 != pool_.end())
		{
			auto &v = p1->second;
			auto p2 = std::find_if(v.begin(), v.end(), [](const UniquePointer &pointer) { return pointer->free; });
			if (p2 != v.end())
			{
				if ((*p2)->connection->isValid())
				{
                    logger::get()->debug("connection {0}:{1} is valid", key, (*p2)->id);
					(*p2)->free = false;
					return new ReleaseGuard((*p2).get());
				}

                logger::get()->debug("connection {0}:{1} is not valid", key, (*p2)->id);
				v.erase(p2);
			}
		}

		const std::string &username = parameters["username"];
		const std::string &password = parameters["password"];

		auto driver = get_driver_instance();
		auto pointer = new Pointer(driver->connect("tcp://" + server, username, password), last_id_++);
		pointer->connection->setSchema(schema);

        logger::get()->debug("add connection {0}:{1} to pool", key, pointer->id);
		if (pool_.find(key) == pool_.end())
		{
			pool_[key] = PointerVector();
		}
		pool_[key].emplace_back(UniquePointer(pointer));

		return new ReleaseGuard(pointer);
	}

private:
	const json &settings_;
	int last_id_;
	std::mutex mutex_;
	Pool pool_;
};

}
}
