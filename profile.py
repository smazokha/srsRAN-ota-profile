#!/usr/bin/python
"""
srsRAN 5G NR Over-the-Air Profile for POWDER Indoor OTA Lab

This profile deploys a complete 5G SA network using:
  - Open5GS 5G Core (AMF, SMF, UPF, NRF, etc.)
  - srsRAN Project gNodeB (transmitting OTA via NI X310 USRP)
  - Up to 4 COTS UEs (Quectel RM520N-GL 5G modems on Intel NUCs)

Architecture:
  [d430 comp node] -- 10GbE -- [ota-x310-N] ~~~OTA~~~ [ota-nucN+Quectel] x 4

The d430 compute node (paired with the X310) runs both Open5GS 5GC and
the srsRAN gNodeB. Each NUC manages its attached Quectel RM520N modem
via AT commands / QMI for COTS UE operation.

After instantiation, wait for startup scripts to finish, then:
  1. On compute node:  sudo /local/repository/scripts/start-5gc.sh
  2. On compute node:  sudo /local/repository/scripts/start-gnb.sh
  3. On each NUC:      sudo /local/repository/scripts/start-ue.sh
  4. iperf3 tests:     see /local/repository/scripts/run-iperf-test.sh

Based on PowderProfiles/srslte-otalab profile conventions for the Indoor OTA Lab.
"""

import os

import geni.portal as portal
import geni.rspec.pg as rspec
import geni.rspec.emulab.pnext as pn
import geni.rspec.igext as ig
import geni.rspec.emulab.spectrum as spectrum


class GLOBALS:
    BIN_PATH = "/local/repository/scripts"
    UBUNTU22_IMG = "urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU22-64-STD"
    MNGR_ID = "urn:publicid:IDN+emulab.net+authority+cm"
    # CBRS frequency defaults for Indoor OTA Lab
    DLDEFLOFREQ = 3580.0
    DLDEFHIFREQ = 3600.0
    ULDEFLOFREQ = 3550.0
    ULDEFHIFREQ = 3570.0


# ---------------------------------------------------------------------------
# Helper: create X310 + compute node pair (matches srslte-otalab pattern)
# ---------------------------------------------------------------------------
def x310_node_pair(idx, x310_radio_name):
    """Allocate a compute node paired with an OTA lab X310 via 10GbE link."""
    radio_link = request.Link("radio-link-%d" % idx)
    radio_link.bandwidth = 10 * 1000 * 1000  # 10 Gbps

    # Compute node (runs gNodeB + 5GC)
    node = request.RawPC("%s-comp" % x310_radio_name)
    node.hardware_type = params.x310_pair_nodetype
    node.disk_image = GLOBALS.UBUNTU22_IMG
    node.component_manager_id = GLOBALS.MNGR_ID

    # Boot-time services
    node.addService(rspec.Execute(
        shell="bash",
        command="%s/add-nat-and-ip-forwarding.sh" % GLOBALS.BIN_PATH))
    node.addService(rspec.Execute(
        shell="bash",
        command="%s/tune-cpu.sh" % GLOBALS.BIN_PATH))
    node.addService(rspec.Execute(
        shell="bash",
        command="%s/tune-sdr-iface.sh" % GLOBALS.BIN_PATH))
    node.addService(rspec.Execute(
        shell="bash",
        command="{bin}/setup-gnb-core.sh '{commit}' 'n78' {arfcn} {bw} {freq}".format(
            bin=GLOBALS.BIN_PATH,
            commit=params.srsran_commit,
            arfcn=params.dl_arfcn,
            bw=params.channel_bw_mhz,
            freq=(params.dl_freq_min + params.dl_freq_max) / 2.0,
        )))

    # 10GbE interface to X310 -- IP 192.168.40.1/24
    node_radio_if = node.addInterface("usrp_if")
    node_radio_if.addAddress(rspec.IPv4Address("192.168.40.1",
                                               "255.255.255.0"))
    radio_link.addInterface(node_radio_if)

    # X310 SDR (fixed OTA lab resource, allocated by component_id)
    radio = request.RawPC("%s-radio" % x310_radio_name)
    radio.component_id = x310_radio_name
    radio.component_manager_id = GLOBALS.MNGR_ID
    radio_link.addNode(radio)

    return node


# ---------------------------------------------------------------------------
# Helper: create NUC node with Quectel COTS UE
# ---------------------------------------------------------------------------
def nuc_ue_node(idx, nuc_node_id):
    """Allocate an OTA lab NUC node for COTS UE operation."""
    node = request.RawPC("%s-ue" % nuc_node_id)
    node.component_id = nuc_node_id
    node.disk_image = GLOBALS.UBUNTU22_IMG

    # Boot-time services
    node.addService(rspec.Execute(
        shell="bash",
        command="%s/tune-cpu.sh" % GLOBALS.BIN_PATH))
    node.addService(rspec.Execute(
        shell="bash",
        command="{bin}/setup-ue.sh {idx}".format(
            bin=GLOBALS.BIN_PATH, idx=idx)))

    return node


# ---------------------------------------------------------------------------
# Portal parameters
# ---------------------------------------------------------------------------
node_type = [
    ("d430", "Emulab, d430"),
    ("d740", "Emulab, d740"),
]

portal.context.defineParameter(
    "x310_pair_nodetype",
    "Type of compute node paired with the X310 Radio",
    portal.ParameterType.STRING,
    node_type[0],
    node_type,
)

lab_x310_names = [
    "ota-x310-1",
    "ota-x310-2",
    "ota-x310-3",
    "ota-x310-4",
]

portal.context.defineStructParameter(
    "x310_radios", "OTA Lab X310 Radios", [],
    multiValue=True,
    itemDefaultValue={},
    min=1, max=1,
    members=[
        portal.Parameter(
            "radio_name",
            "OTA Lab X310",
            portal.ParameterType.STRING,
            lab_x310_names[0],
            lab_x310_names,
        )
    ],
)

ota_nuc_names = [
    "ota-nuc1",
    "ota-nuc2",
    "ota-nuc3",
    "ota-nuc4",
]

portal.context.defineStructParameter(
    "nuc_nodes", "OTA Lab NUC UE Nodes", [],
    multiValue=True,
    min=1, max=None,
    members=[
        portal.Parameter(
            "node_id",
            "OTA Lab NUC (with Quectel RM520N)",
            portal.ParameterType.STRING,
            ota_nuc_names[0],
            ota_nuc_names,
        )
    ],
)

portal.context.defineParameter(
    "srsran_commit",
    "srsRAN Project git commit/tag/branch",
    portal.ParameterType.STRING,
    "main",
    longDescription="Git ref for the srsRAN_Project repository to build from source.",
)

portal.context.defineParameter(
    "dl_arfcn",
    "Downlink NR-ARFCN",
    portal.ParameterType.INTEGER,
    640000,
    longDescription="NR-ARFCN for the DL carrier center. "
                    "640000 = 3600 MHz (band n78). Adjust to match your "
                    "frequency allocation.",
)

portal.context.defineParameter(
    "channel_bw_mhz",
    "Channel bandwidth (MHz)",
    portal.ParameterType.INTEGER,
    20,
    legalValues=[10, 20, 40],
    longDescription="Channel bandwidth in MHz. Must not exceed allocated spectrum.",
)

portal.context.defineParameter(
    "ul_freq_min",
    "Uplink Frequency Min (MHz)",
    portal.ParameterType.BANDWIDTH,
    GLOBALS.ULDEFLOFREQ,
    longDescription="Values are rounded to the nearest kilohertz.",
)
portal.context.defineParameter(
    "ul_freq_max",
    "Uplink Frequency Max (MHz)",
    portal.ParameterType.BANDWIDTH,
    GLOBALS.ULDEFHIFREQ,
    longDescription="Values are rounded to the nearest kilohertz.",
)
portal.context.defineParameter(
    "dl_freq_min",
    "Downlink Frequency Min (MHz)",
    portal.ParameterType.BANDWIDTH,
    GLOBALS.DLDEFLOFREQ,
    longDescription="Values are rounded to the nearest kilohertz.",
)
portal.context.defineParameter(
    "dl_freq_max",
    "Downlink Frequency Max (MHz)",
    portal.ParameterType.BANDWIDTH,
    GLOBALS.DLDEFHIFREQ,
    longDescription="Values are rounded to the nearest kilohertz.",
)

# ---------------------------------------------------------------------------
# Bind and validate parameters
# ---------------------------------------------------------------------------
params = portal.context.bindParameters()

# Validate CBRS frequency ranges
if params.ul_freq_min < 3358 or params.ul_freq_min > 3600 \
   or params.ul_freq_max < 3358 or params.ul_freq_max > 3600:
    perr = portal.ParameterError(
        "C-band uplink frequencies must be between 3358 and 3600 MHz",
        ["ul_freq_min", "ul_freq_max"])
    portal.context.reportError(perr)
if params.ul_freq_max - params.ul_freq_min < 1:
    perr = portal.ParameterError(
        "Min and max frequencies must be separated by at least 1 MHz",
        ["ul_freq_min", "ul_freq_max"])
    portal.context.reportError(perr)
if params.dl_freq_min < 3358 or params.dl_freq_min > 3600 \
   or params.dl_freq_max < 3358 or params.dl_freq_max > 3600:
    perr = portal.ParameterError(
        "C-band downlink frequencies must be between 3358 and 3600 MHz",
        ["dl_freq_min", "dl_freq_max"])
    portal.context.reportError(perr)
if params.dl_freq_max - params.dl_freq_min < 1:
    perr = portal.ParameterError(
        "Min and max frequencies must be separated by at least 1 MHz",
        ["dl_freq_min", "dl_freq_max"])
    portal.context.reportError(perr)

portal.context.verifyParameters()

# ---------------------------------------------------------------------------
# Request resources
# ---------------------------------------------------------------------------
request = portal.context.makeRequestRSpec()

# Create X310 + compute node pair(s)
for i, x310_radio in enumerate(params.x310_radios):
    comp_node = x310_node_pair(i, x310_radio.radio_name)

# Create NUC UE nodes
for i, nuc_node in enumerate(params.nuc_nodes):
    nuc_ue_node(i + 1, nuc_node.node_id)

# Request spectrum
request.requestSpectrum(params.ul_freq_min, params.ul_freq_max, 0)
request.requestSpectrum(params.dl_freq_min, params.dl_freq_max, 0)

portal.context.printRequestRSpec()
