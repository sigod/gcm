# gcm

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