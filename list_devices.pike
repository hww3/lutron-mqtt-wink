Public.Protocols.MQTT.MQTTServer server;

#define MQTT_URL "mqtt://192.168.5.50"
Public.Protocols.MQTT.client mqtt;

int main(int argc, array argv) {
    werror("requesting device list\n");
    call_out(start_mqtt_client,1);

  return -1;
}

void start_mqtt_client() {  
  mqtt = Public.Protocols.MQTT.client(MQTT_URL);             
  mqtt->set_client_identifier("pair-" + time());             
  mqtt->set_disconnect_callback(dis_cb);                     
  mqtt->connect(has_connected);                              
  werror("Client: %O\n", mqtt);           
} 

void has_connected(object client) {                          
        werror("Client connected: %O\n", client);            
        client->set_qos_level(0);                
 client->subscribe("lutron/events", pub_cb);            
werror("subscribed\n");
  client->publish("lutron/commands", "foo" , 0, pub_failed);
string payload = Standards.JSON.encode((["cmd": "GetButtonGroups", "args": ([])]));
  client->publish("lutron/commands", payload, 0, pub_failed);
payload = Standards.JSON.encode((["cmd": "GetDevices", "args": ([])]));
  client->publish("lutron/commands", payload, 0, pub_failed);
  call_out(time_out, 10);
}                           


void pub_failed(mixed ... args) {
  werror("publish of message failed with args: %O\n", args);
}

int c;
int checkedremote, checkeddevice;
int remoteid, nameid;
int gotit;
void pub_cb(object client, string topic, string body) {
  c ++;
  mapping json = Standards.JSON.decode(body);
// {"cmd":"DevicePresentResponse","args":{"Status":3,"FirmwareRevision":"255.255","LinkAddress":255,"SerialNumber":25992017,"DeviceClass":70714113}}
  if(json->cmd == "ListDevices") {
     checkeddevice = 1;
     werror("\nDevices\n");
     foreach(json->args;; mapping device) {
	werror(device->LinkAddress + " " + device->Name + " " + device->Description + "\n");
     }
  }
  else if(json->cmd == "ListButtonGroups") {
     werror("\nRemotes\n");
     checkedremote = 1;
     foreach(json->args;; mapping device) {
       werror(device->ButtonGroupID + " " + device->Name + " " + device->Description + "\n");
     }
  }

     if(checkedremote && checkeddevice) {
     remove_call_out(time_out);
       exit(1);
    }
}

void time_out() {
  werror("request timed out. exiting.\n");
  exit(1);
}
    
void dis_cb(object client, object reason) {
        werror("Client disconnected: %O=>%O\n", client, reason);
  call_out(mqtt->connect,2,has_connected);
}                           

