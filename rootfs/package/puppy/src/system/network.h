#pragma once
// The USB network: the data port as an Ethernet adapter the PC or phone on the cable shares its
// internet with (usb-mode.sh network, S31usb-net, usb-net.sh). What the Internet page shows.
#include <string>

struct NetworkStatus {
    bool networkMode = false;       // the cable is the adapter, not the MTP drive
    bool hostUp = false;            // a PC or phone has set the gadget up
    bool linkUp = false;            // and opened the adapter
    std::string address, gateway, dns;
    std::string check;              // the last internet check (usb-net.sh): "ok", "fail", "" for none

    static NetworkStatus read();
};

void setUsbMode(bool network);      // usb-mode.sh: rebuilds the gadget, waits for it
void checkInternet();               // usb-net.sh check, in the background: check follows
void askForAddress();               // usb-net.sh renew: udhcpc asks now
