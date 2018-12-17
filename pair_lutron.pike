Public.Protocols.MQTT.MQTTServer server;

#define MQTT_URL "mqtt://192.168.5.50"
Public.Protocols.MQTT.client mqtt;

string name;

int main(int argc, array argv) {
    name = argv[1];
    werror("entering addressing mode for device name = " + name + "\n");
    call_out(start_mqtt_client,1);

  return -1;
}

void start_mqtt_client() {  
  mqtt = Public.Protocols.MQTT.client(MQTT_URL);             
  mqtt->set_client_identifier("pair-" + time());             
  mqtt->set_disconnect_callback(dis_cb);                     
  werror("Client: %O\n", mqtt);                              
  mqtt->connect(has_connected);                              
  werror("Client: %O\n", mqtt);           
} 

void has_connected(object client) {                          
        werror("Client connected: %O\n", client);            
        client->set_qos_level(0);                
werror("subscribing\n");    
 client->subscribe("lutron/events", pub_cb);            
werror("subscribed\n");
  client->publish("lutron/commands", "foo" , 0, pub_failed);
string payload = Standards.JSON.encode((["cmd": "RequestEnterAddressingMode", "args": ([])]));
werror("payload: %O\n", payload);
  client->publish("lutron/commands", payload, 0, pub_failed);
  call_out(exit_addressing_mode, 60);
}                           

void exit_addressing_mode() {
  mqtt->publish("lutron/commands", Standards.JSON.encode((["cmd": "RequestExitAddressingMode", "args": ([])])), 0, pub_failed);
}

void pub_failed(mixed ... args) {
  werror("publish of message failed with args: %O\n", args);
}

int c;

void pub_cb(object client, string topic, string body) {
  c ++;
  werror("Received message %d: %O, %s -> %O\n", c, client, topic, Standards.JSON.decode(body));
  mapping json = Standards.JSON.decode(body);
// {"cmd":"DevicePresentResponse","args":{"Status":3,"FirmwareRevision":"255.255","LinkAddress":255,"SerialNumber":25992017,"DeviceClass":70714113}}
  if(json->cmd == "DevicePresentResponse") {
     werror("Got a device identifier\n");
     remove_call_out(exit_addressing_mode);
     string payload = Standards.JSON.encode((["cmd": "RequestAddressDevice", "args": (["Name": name, "SerialNumber": json->args->SerialNumber, "DeviceClass": json->args->DeviceClass])]));
  
     mqtt->publish("lutron/commands", payload, 0, pub_failed);
     call_out(exit_addressing_mode, 5);
  }
}
    
void dis_cb(object client, object reason) {
        werror("Client disconnected: %O=>%O\n", client, reason);
  call_out(mqtt->connect,2,has_connected);
}                           

