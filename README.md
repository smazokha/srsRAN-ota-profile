# srsRAN 5G NR Over-the-Air POWDER Profile

A POWDER/Emulab experiment profile that deploys a complete 5G Standalone (SA) network using open-source components and COTS UEs over the air.

## Architecture

```
┌─────────────────────────────┐        ┌──────────────┐
│  d430 Node                  │  10GbE │  NI X310     │
│                             │◄──────►│  USRP        │
│  ┌─────────┐  ┌───────────┐│        │  (UBX160)    │
│  │ Open5GS │  │ srsRAN    ││        └──────┬───────┘
│  │ 5GC     │  │ gNodeB    ││               │ OTA
│  │         │  │           ││               │
│  │ AMF,SMF │  │ Band n78  ││        ┌──────┴───────┐
│  │ UPF,NRF │  │ 20 MHz    ││        │              │
│  │ ...     │  │           ││   ┌────┴──┐ ┌────┴──┐
│  └─────────┘  └───────────┘│   │ NUC1  │ │ NUC4  │
└─────────────────────────────┘   │Quectel│ │Quectel│
                                  │RM520N │…│RM520N │
                                  └───────┘ └───────┘
```

## Components

| Node | Hardware | Software | Role |
|------|----------|----------|------|
| gnb | d430 + X310 USRP | Open5GS, srsRAN Project | 5G Core + gNodeB |
| nuc1-4 | Intel NUC + Quectel RM520N | ModemManager, QMI tools | COTS 5G UE |

## Quick Start

1. **Instantiate** the profile on POWDER with your reserved resources
2. **Wait** for setup scripts to finish (check `/var/log/startup-*.log`)
3. **On the gNB node:**
   ```bash
   sudo /local/repository/scripts/start-5gc.sh    # Start 5G core
   sudo /local/repository/scripts/start-gnb.sh     # Start gNodeB
   ```
4. **On each NUC:**
   ```bash
   sudo /local/repository/scripts/start-ue.sh      # Attach modem to cell
   modem-status                                      # Check registration
   ```
5. **Run iperf3 tests:**
   ```bash
   # On gNB node:
   sudo /local/repository/scripts/run-iperf-test.sh

   # On each NUC:
   iperf3 -c 10.45.0.1 -p 5201 -t 10       # Uplink
   iperf3 -c 10.45.0.1 -p 5201 -t 10 -R    # Downlink
   ```

## Configuration

### Parameters (set at instantiation)

| Parameter | Default | Description |
|-----------|---------|-------------|
| num_ues | 4 | Number of NUC+Quectel UE nodes (1-4) |
| gnb_hardware_type | d430 | Hardware type for gNB/core node |
| nr_band | n78 | NR frequency band |
| dl_arfcn | 640000 | Downlink ARFCN (3600 MHz for n78) |
| channel_bw_mhz | 20 | Channel bandwidth in MHz |
| srsran_commit | main | srsRAN Project git ref to build |

### Key Files

| File | Location (on gNB node) | Purpose |
|------|----------------------|---------|
| gnb.yml | /etc/srsran/gnb.yml | gNodeB radio + core config |
| amf.yaml | /etc/open5gs/amf.yaml | AMF (NGAP, PLMN, TAI) |
| upf.yaml | /etc/open5gs/upf.yaml | UPF (GTP-U, subnets) |
| smf.yaml | /etc/open5gs/smf.yaml | SMF (session, DNS) |
| subscribers.csv | /local/repository/config/ | Test SIM credentials |

### Test Subscribers

4 pre-provisioned subscribers use the standard test PLMN (001/01) with default srsRAN/Open5GS credentials. Update `config/subscribers.csv` with your actual SIM K/OPC values if using programmable SIMs.

## Troubleshooting

- **gNB can't find X310**: Check `uhd_find_devices --args="type=x300"` and verify 10GbE connectivity
- **UE won't register**: Verify gNB is transmitting (`/tmp/gnb.log`), check `modem-status` on NUC
- **No data connection**: Check UPF TUN device (`ip addr show ogstun`), verify NAT rules
- **iperf3 no connectivity**: Ensure UE has IP on wwan interface, check routing to 10.45.0.0/16

## File Structure

```
├── profile.py              # Emulab/POWDER profile definition
├── config/
│   ├── gnb.yml             # srsRAN gNodeB config (template)
│   ├── open5gs-amf.yaml    # Open5GS AMF config (template)
│   ├── open5gs-upf.yaml    # Open5GS UPF config (template)
│   ├── open5gs-smf.yaml    # Open5GS SMF config (template)
│   └── subscribers.csv     # Test subscriber credentials
├── scripts/
│   ├── setup-gnb-core.sh   # Bootstrap: installs Open5GS + builds srsRAN
│   ├── setup-ue.sh         # Bootstrap: installs modem tools on NUCs
│   ├── start-5gc.sh        # Runtime: start Open5GS services
│   ├── start-gnb.sh        # Runtime: start srsRAN gNodeB
│   ├── start-ue.sh         # Runtime: attach Quectel modem to cell
│   ├── stop-all.sh         # Runtime: stop gNB + 5GC
│   └── run-iperf-test.sh   # Testing: iperf3 throughput tests
└── README.md
```
