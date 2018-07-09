#pragma once

#include <string>

#include <crypto++/hex.h>

#define CRYPTOPP_ENABLE_NAMESPACE_WEAK 1
#include <crypto++/md5.h>

namespace machine
{

class HashBuilder
{
public:
	void update(const std::string &message)
	{
		hash.Update((const byte *)message.c_str(), message.length());
	}

	std::string final()
	{
		byte digest[CryptoPP::Weak::MD5::DIGESTSIZE];
		hash.Final(digest);

		CryptoPP::HexEncoder encoder;
		std::string output;

		encoder.Attach(new CryptoPP::StringSink(output));
		encoder.Put(digest, sizeof(digest));
		encoder.MessageEnd();

        std::transform(output.begin(), output.end(), output.begin(), ::tolower);

		return output;
	}
private:
	CryptoPP::Weak::MD5 hash;
};

}
