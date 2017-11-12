#pragma once

#include <cstdlib>
#include <iostream>
#include <memory>
#include <utility>
#include <array>
#include <string>

#include <boost/asio.hpp>
#include <spdlog/spdlog.h>

#include "processor.hpp"

using boost::asio::ip::tcp;

namespace machine
{

class Session : public std::enable_shared_from_this<Session>
{
public:
	explicit Session(tcp::socket socket) : socket_(std::move(socket)) {}

	void start()
	{
		doRead();
	}

private:
	void doRead()
	{
		auto self(shared_from_this());
		socket_.async_read_some(boost::asio::buffer(buffer_, buffer_.size()), [this, self](boost::system::error_code error, size_t length) {
			auto console = spdlog::get("console");
			if (!error)
			{
				auto p = std::find(buffer_.begin(), buffer_.end(), 0x04);
				if (p == buffer_.end())
				{
					request_.append(buffer_.begin(), length);
					doRead();
				}
				else
				{
					request_.append(buffer_.begin(), p);
					doWrite(processor_.process(request_));
				}
			}
			else
			{
				console->error(error.message());
			}
		});
	}

	void doWrite(const std::string &response)
	{
		auto self(shared_from_this());
		std::string buffer = response + char(0x04);
		boost::asio::async_write(socket_, boost::asio::buffer(buffer), [this, self](boost::system::error_code error, std::size_t /*length*/) {
			if (error)
			{
				auto console = spdlog::get("console");
				console->error(error.message());
			}
		});
	}

	tcp::socket socket_;
	std::array<char, 1024> buffer_;
	std::string request_;
	Processor processor_;
};

class Server
{
public:
	Server(boost::asio::io_service &io_service, short port) : acceptor_(io_service, tcp::endpoint(tcp::v4(), port)), socket_(io_service)
	{
		doAccept();
	}

private:
	void doAccept()
	{
		acceptor_.async_accept(socket_, [this](boost::system::error_code error) {
			if (!error)
			{
				std::make_shared<Session>(std::move(socket_))->start();
			}
			doAccept();
		});
	}

	tcp::acceptor acceptor_;
	tcp::socket socket_;
};

void start(short port)
{
	boost::asio::io_service io_service;
	machine::Server server(io_service, port);
	io_service.run();
}

}
