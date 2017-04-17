# gcm

[![Join the chat at https://gitter.im/sigod/gcm](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/sigod/gcm?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

[![Build Status](https://travis-ci.org/sigod/gcm.svg?branch=master)](https://travis-ci.org/sigod/gcm)
[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/sigod/gcm?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

Google Cloud Messaging (GCM) for D

## Usage

```d
import gcm;

void main()
{
	immutable GCM_KEY = ".. key ..";

	// simple
	{
		auto message = gcmessage(["message": "This is a GCM Topic Message!"]);
		message.dry_run = true;

		auto response = GCM_KEY.sendTopic("/topics/test", message);
		assert(response.message_id == -1);
	}

	// user defined data types
	{
		static struct CustomData
		{
			string message;
		}

		auto message = gcmessage(CustomData("This is a GCM Topic Message!"));
		message.dry_run = true;

		auto response = GCM_KEY.sendTopic("/topics/test", message);
		assert(response.message_id == -1);
	}
}
```
