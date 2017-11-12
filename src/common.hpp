#pragma once

#include <json.hpp>

namespace machine
{
using json = nlohmann::json;

void merge(const json &from, json &to)
{
    //auto console = spdlog::get("console");
    //console->debug("merge result from {0} to {1}", from.dump(), to.dump());

    for (json::const_iterator j = from.begin(); j != from.end(); j++)
    {
        if (j.value().is_object())
        {
            auto p = to.find(j.key());
            if (p != to.end())
            {
                merge(j.value(), *p);
            }
            else
            {
                to[j.key()] = j.value();
            }
        }
        else if (j.value().is_array())
        {
            // TODO merge array?
        }
        else
        {
            to[j.key()] = j.value();
        }
    }
}
}
