# gcm

[![Join the chat at https://gitter.im/sigod/gcm](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/sigod/gcm?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

[![Build Status](https://travis-ci.org/sigod/gcm.svg?branch=master)](https://travis-ci.org/sigod/gcm)

Google Cloud Messaging (GCM) for D

## Usage

```d
import gcm;

void main()
{
	auto gcm = new GCM("api key here");

	// simple
	{
		auto message = gcmessage("/topics/test");
		message.data = ["message": "This is a GCM Topic Message!"];
		message.dry_run = true;
		auto response = gcm.send(message);

		assert(response.message_id == "-1");
	}

	// user defined data types
	{
		static struct CustomData
		{
			string message;
		}

		auto custom_data = CustomData("This is a GCM Topic Message!");

		auto message = gcmessage("/topics/test", custom_data);
		message.dry_run = true;
		auto response = gcm.send(message);

		assert(response.message_id == "-1");
	}
}
```