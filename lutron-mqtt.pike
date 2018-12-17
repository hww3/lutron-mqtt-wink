#!/usr/local/bin/pike

#define MQTT_URL "mqtt://localhost"
#define LUTRON_SOCKET "/tmp/lutron-core.sock"
#define LUTRON_DATABASE "/database/lutron-db.sqlite"

constant default_port = 8080;
constant my_version = "0.0";

Public.Protocols.MQTT.client mqtt;
Protocols.HTTP.Server.Port port;
Protocols.DNS_SD.Service dns_sd;
Public.Protocols.MQTT.MQTTServer server;

object db = Sql.Sql("sqlite://" + LUTRON_DATABASE);
object lutron_sock;
object lutron_proxy;
string lutron_buffer = "";

mapping buttons = ([
	0x02: "on",
	0x04: "off",
	0x05: "up",
	0x06: "down",
	0x03: "select",
]);

int main(int argc, array(string) argv)
{
  int my_port = default_port;
  if(argc>1) my_port=(int)argv[1];

  write("FinServe starting on port " + my_port + "\n");
  call_out(start_mqtt_client,1);
  port = Protocols.HTTP.Server.Port(handle_request, my_port);
  werror(Process.popen("/etc/rc.d/init.d/lutron stop"));
  werror("starting lutron proxy\n");
  open_proxy();
  werror("monit should restart lutron core shortly.\n");
  call_out(connect_to_core, 15);
  call_out(register_service, 16);
  return -1;
}

void start_mqtt_client() {
  mqtt = Public.Protocols.MQTT.client(MQTT_URL);             
  mqtt->set_client_identifier("hww3-" + time());             
  mqtt->set_disconnect_callback(dis_cb);                     
  werror("Client: %O\n", mqtt);                              
  mqtt->connect(has_connected);                              
  werror("Client: %O\n", mqtt);           
}

void blink() {
  werror("blink\n");
  Process.popen("/usr/sbin/setrgb 00ff00:400 0000ff:400");
}

void register_service() {
  dns_sd = Protocols.DNS_SD.Service("Hacienda", "_lutron_mqtt._tcp", "", 1883, ({"uuid=" + Standards.UUID.make_version4()->str()}));
}

void connect_to_core() {
werror("connecting to lutron-core\n");
  lutron_sock = Stdio.File();
  if(!lutron_sock->connect_unix(LUTRON_SOCKET)) 
	throw(Error.Generic("Unable to connect to lutron-core\n"));
  lutron_sock->set_nonblocking(lutron_read, lutron_write, lutron_close);
werror("connected.\n");
  call_out(up_and_running, 0);
}

void up_and_running() {
  Process.popen("/usr/sbin/setrgb 0000ff:100000");
  werror("back to the business\n");
  mqtt->publish("lutron/status", Standards.JSON.encode((["state": "started"])), 0, pub_failed);
  call_out(still_running, 30);
}

void still_running() {
  // todo check for anything that might indicate a non-good status
  mqtt->publish("lutron/status", Standards.JSON.encode((["state": "running"])), 0, pub_failed);
  call_out(still_running, 30);
}

void open_proxy() {
  lutron_proxy = ((program)"serial_to_pty")("/dev/ttySP2", "/tmp/lutronTty", lutron_proxy_closed, lutron_radio_data);
}

string data_buffer = "";

void lutron_radio_data(mixed data) {
  string d;
  int state;
  data_buffer += data;

  string data_buffer2;
 werror("got data: %O\n", data);
  do {
  sscanf(data_buffer, "%*s~%s~%s", d, data_buffer2);
  if(d) data_buffer = data_buffer2;
  else return; // not a complete message.

  sscanf(d, "\1%*s\5\0%s", d);
  if(d && sizeof(d) > 6) {
     switch(d[7]) {
      case '\0':
        werror("button press: %X%X%X: %s down\n", d[2], d[3], d[4], buttons[d[6]]||"?");
        mqtt->publish("lutron/remote", 
		sprintf("{\"serial\" : \"%X%X%X\", \"action\": \"down\", \"button\": \"%s\"}", d[2], d[3], d[4], buttons[d[6]]||"??"),
		0, pub_failed);
        break;
      case '\1': 
        werror("button press: %X%X%X: %s up\n", d[2], d[3], d[4], buttons[d[6]]||"?");
	blink();
	mqtt->publish("lutron/remote",                                                                                                        
                sprintf("{\"serial\" : \"%X%X%X\", \"action\": \"up\", \"button\": \"%s\"}", d[2], d[3], d[4], buttons[d[6]]||"??"), 
                0, pub_failed); 
        break;
    }
  }
 } while(sizeof(data_buffer)); 
}

void lutron_proxy_closed(object proxy) {
  werror("lutron proxy closed: %O\n", proxy);
  call_out(open_proxy, 5);
}

void pub_failed(mixed ... args) {
  werror("publish of message failed with args: %O\n", args);
}

int c = 0;
void pub_cb(object client, string topic, string body) {
  c ++;
  werror("Received message %d: %O, %s -> %O\n", c, client, topic, Standards.JSON.decode(body));
  mapping json = Standards.JSON.decode(body);
  if(json) client->publish("lutron/events", Standards.JSON.encode(handle_cmd(json)), 0, pub_failed);

  if(0 && c > 2) {
        client->unsubscribe(topic, pub_cb);
        client->disconnect();
  }                        
}                          
                           
void dis_cb(object client, object reason) {
        werror("Client disconnected: %O=>%O\n", client, reason);
  call_out(mqtt->connect,2,has_connected);
}   

void has_connected(object client) {                          
        werror("Client connected: %O\n", client);            
        client->set_qos_level(0);                
werror("subscribing\n");
 client->subscribe("lutron/commands", pub_cb);            
werror("subscribed\n");
}  

void lutron_read(mixed id, string data) {
werror("lutron_read: %O\n", data);
  streaming_decode(data, publish_event); 
}

string decode_buffer = "";
int brace_count = 0;
int last_pos = 0;

void streaming_decode(string data, function event) {
  decode_buffer += data;
  int len = sizeof(decode_buffer);
  if(!len) return;
  for(; last_pos < len; last_pos++) {
    if(sizeof(decode_buffer)<=last_pos) continue; 
    if(decode_buffer[last_pos] == '{') {
      brace_count++;
    } else if(decode_buffer[last_pos] == '}') {
      brace_count--; 
      if(brace_count == 0) {
        werror("sending json for decode: \n\n" + decode_buffer[0..last_pos] + "\n\n");
        mixed json = Standards.JSON.decode(decode_buffer[0..last_pos]);
        if(len > last_pos+1) {
          decode_buffer = decode_buffer[last_pos+1..];
          werror("decode buffer is now: %O\n", decode_buffer);	
          len = sizeof(decode_buffer);
        }
        else decode_buffer = "", len=0;
        last_pos = -1;
        blink();
        event(json);
      } else if(brace_count < 0) {
          throw(Error.Generic("brace_count reached " + brace_count + " in decode_buffer " + decode_buffer));
      }
    }
  } 
  
}

void publish_event(mixed json) {
  if(json && json->cmd == "RuntimePropertyUpdate") blink();
  if(json) mqtt->publish("lutron/events", Standards.JSON.encode(json), 0, pub_failed);
}

void lutron_write(mixed id) {
werror("lutron_write: %O\n", lutron_buffer);
  if(!sizeof(lutron_buffer)) return 0;
werror("have %d to send.\n", sizeof(lutron_buffer));
  int x = lutron_sock->write(lutron_buffer);
werror("sent %d\n", x);
  if(x == sizeof(lutron_buffer)) 
    lutron_buffer = "";
  else 
    lutron_buffer = lutron_buffer[x..];
  return;
}

void lutron_close(mixed id) {
werror("lutron_close\n");
}

mapping response_json_required() {
  return (["type":"text/html", "error": 400, "data": "Request must be JSON.\n"]);
}

mapping response_cmd_required() {                                                                          
  return (["type":"text/html", "error": 400, "data": "Request field 'cmd' is required.\n"]);                             
} 

mixed send_lutron_cmd(string cmd, array args) {
string json = Standards.JSON.encode((["cmd": cmd, "args": args])) ;
  werror("sending json: %s\n", json);
  int sent;
json+="\n";
//  do {
    sent = lutron_sock->write(json);
if(sent < 0) {werror("whoops.\n"); }
werror("sent: %d - %s\n", sent, json[0..(sent?(sent-1):0)]);
    if(sent < sizeof(json)) {
       lutron_buffer += json[sent ..];
       werror("queued.\n");
    }
    else {
     werror("sent.\n");
    }
}

mapping handle_cmd(mapping json) {

  switch(json->cmd) {
    case "GetDevices":
      return (["cmd": "ListDevices", "args": 
	db->query("select GetProjectDevices.*,Device.LinkAddress as LinkAddress from GetProjectDevices,Device where GetProjectDevices.IntegrationId in(Select IntegrationId from GetProjectOutputDevices) and GetProjectDevices.DeviceId=Device.DeviceId")]);
//	db->query("select * from GetProjectDevices where IntegrationId in(Select IntegrationId from GetProjectOutputDevices)")]);
      break;
    case "GetButtonGroups":
      return (["cmd": "ListButtonGroups", "args":
        db->query("select buttongroup.*, device.name,deviceinfo.* from buttongroup,device,deviceinfo " +
         "where buttongroup.deviceid = device.deviceid and deviceinfo.deviceinfoid=device.DeviceInfoId")
	]);
      break;
    case "GoToLevel":
    case "RuntimePropertyQuery":
    case "Ping":
    case "RequestEnterAddressingMode":
    case "RequestExitAddressingMode":
    case "RequestAddressDevice":
    case "RequestUnaddressDevice":
    case "RequestAddColumnProgramming":
    case "RequestDeleteColumnProgramming":
      blink();
      send_lutron_cmd(json->cmd, json->args);
//      return (["result": lutron_sock->read(1024, 1)]);
      return (["result": "Request " + json->cmd + " Sent."]);
      break;
    default:
      return (["error": "Unrecognized command " + json->cmd ]);
  }

  return 0;
}

void handle_request(Protocols.HTTP.Server.Request request)
{
  write(sprintf("got request: %O\n", request));
  if(request->request_headers["content-type"] != "application/json") {
    request->response_and_finish(response_json_required());
    return 0;
  }

  mapping json = Standards.JSON.decode(request->body_raw);
  if(!json || !json->cmd) {
    request->response_and_finish(response_cmd_required()); 
    return 0;
  }
  mapping response = ([]);

  response->server="FinServe " + my_version;
  response->type = "application/json";
  response->error = 200;
  mixed e;
  if(e = catch(  response->data = Standards.JSON.encode(handle_cmd(json)) ))
    response->data = "{\"error\": \"" + Error.mkerror(e)->describe() + "\"}";

  request->response_and_finish(response);
}
