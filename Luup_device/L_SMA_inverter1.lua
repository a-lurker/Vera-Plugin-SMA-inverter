-- Vera code originated by crepuscule and is based on SBFspot code
-- Modifications, additions, PVOutput.org send and plugin code by a-lurker: Sept 2016

-- http://sbfspot.codeplex.com/
-- http://forum.micasaverde.com/index.php?topic=23657.0

--[[
	SBFspot - Yet another tool to read power production of SMA® solar inverters
	(c)2012-2015, SBF

	Latest version found at https://sbfspot.codeplex.com

	License: Attribution-NonCommercial-ShareAlike 3.0 Unported (CC BY-NC-SA 3.0)
	http://creativecommons.org/licenses/by-nc-sa/3.0/

	You are free:
		to Share - to copy, distribute and transmit the work
		to Remix - to adapt the work
	Under the following conditions:
	Attribution:
		You must attribute the work in the manner specified by the author or licensor
		(but not in any way that suggests that they endorse you or your use of the work).
	Non commercial:
		You may not use this work for commercial purposes.
	Share Alike:
		If you alter, transform, or build upon this work, you may distribute the resulting work
		only under the same or similar license to this one.

DISCLAIMER:
	A user of SBFspot software acknowledges that he or she is receiving this
	software on an "as is" basis and the user is not relying on the accuracy
	or functionality of the software for any purpose. The user further
	acknowledges that any use of this software will be at his own risk
	and the copyright owner accepts no responsibility whatsoever arising from
	the use or application of the software.

	SMA is a registered trademark of SMA Solar Technology AG
]]

-- this code suits most SMA inverters
local PLUGIN_NAME     = 'SMA_inverter'
local PLUGIN_SID      = 'urn:a-lurker-com:serviceId:'..PLUGIN_NAME..'1'
local PLUGIN_VERSION  = '0.54'
local THIS_LUL_DEVICE = nil

local m_first_time = true

-- set PW_USER equal to your password, if not the default
-- pw allows the following chars: length 4 to 12 chars: A-Z, a-z, 0-9, ? _ | -
-- try to log in as a "user" with the default password "0000"
local PW_USER = '0000'

local HA_SID           = 'urn:micasaverde-com:serviceId:HaDevice1'
local ENERGY_METER_SID = 'urn:micasaverde-com:serviceId:EnergyMetering1'
local TEMP_SENSOR_SID  = 'urn:upnp-org:serviceId:TemperatureSensor1'

local IP_PORT   = 9522
local ipAddress = ''

local FIVE_MIN_IN_SECS = 300
local m_PollInterval   = FIVE_MIN_IN_SECS
local m_PollEnable     = ''  -- is set to either: '0' or '1'

local ETH_L2_SIGNATURE       = 0x65601000
local BTH_L2_SIGNATURE       = 0x656003FF
local ENERGY_METER_SIGNATURE = 0x69601000


-- ANY_DEST_SUSY_ID and ANY_DEST_SERIAL_NUMBER can replace DEST_SUSY_ID and DEST_SERIAL_NUMBER if needed:
local ANY_DEST_SUSY_ID       = 0xffff
local ANY_DEST_SERIAL_NUMBER = 0xffffffff

local DEST_SUSY_ID           = ANY_DEST_SUSY_ID
local DEST_SERIAL_NUMBER     = ANY_DEST_SERIAL_NUMBER

--[[
local DEST_SUSY_ID = 0x00b5

-- replace 0x12345678 with your 12 digit decimal serial number, as written on your inverter, expressed in hex
local DEST_SERIAL_NUMBER = 0x12345678
]]

local PKT_LEN_POS = 14
local PKT_EXCLUDE = 20

-- this will hold the most recent results. Values may be nil
local inverterData = {}

local AppSUSyID = nil
local AppSerial = nil

-- packet ids, not used
local smaPacketID = 1

local m_PVOutputApiKey   = ''
local m_PVOutputSystemID = ''

local COMMANDS = {
--[[
    TestCmd1 = {
        command = 0x51000200,
        first   = 0x00260000,
        last    = 0x0026ffff},
]]
    EnergyProduction = {
        -- SPOT_ETODAY, SPOT_ETOTAL -- command: total energy all time
                                -- cmd_total_today
        command = 0x54000200,   -- 0x54000200
        first   = 0x00260100,   -- 0x00260000
        last    = 0x002622FF},  -- 0x0026FFFF
    SpotDCPower = {
        -- SPOT_PDC1, SPOT_PDC2
        command = 0x53800200,
        first   = 0x00251E00,
        last    = 0x00251EFF},
    SpotDCVoltage = {
        -- SPOT_UDC1, SPOT_UDC2, SPOT_IDC1, SPOT_IDC2
        command = 0x53800200,
        first   = 0x00451F00,
        last    = 0x004521FF},
    SpotACPower = {
        -- SPOT_PAC1, SPOT_PAC2, SPOT_PAC3
        command = 0x51000200,
        first   = 0x00464000,
        last    = 0x004642FF},
    SpotACVoltage = {
        -- SPOT_UAC1, SPOT_UAC2, SPOT_UAC3, SPOT_IAC1, SPOT_IAC2, SPOT_IAC3
        command = 0x51000200,
        first   = 0x00464800,
        last    = 0x004655FF},
    SpotGridFrequency = {
        -- SPOT_FREQ
        command = 0x51000200,
        first   = 0x00465700,
        last    = 0x004657FF},
    MaxACPower = {
        -- INV_PACMAX1, INV_PACMAX2, INV_PACMAX3
        command = 0x51000200,
        first   = 0x00411E00,
        last    = 0x004120FF},
    MaxACPower2 = {
        -- INV_PACMAX1_2
        command = 0x51000200,
        first   = 0x00832A00,
        last    = 0x00832AFF},
    SpotACTotalPower = {
        -- SPOT_PACTOT
        command = 0x51000200,
        first   = 0x00263F00,
        last    = 0x00263FFF},
    TypeLabel = {
        -- INV_NAME, INV_TYPE, INV_CLASS
        command = 0x58000200,
        first   = 0x00821E00,
        last    = 0x008220FF},
    SoftwareVersion = {
        -- INV_SWVERSION
        command = 0x58000200,
        first   = 0x00823400,
        last    = 0x008234FF},
    DeviceStatus = {
        -- INV_STATUS
        command = 0x51800200,
        first   = 0x00214800,
        last    = 0x002148FF},
    GridRelayStatus = {
        -- INV_GRIDRELAY
        command = 0x51800200,
        first   = 0x00416400,
        last    = 0x004164FF},
    OperationTime = {
        -- SPOT_OPERTM, SPOT_FEEDTM
        command = 0x54000200,
        first   = 0x00462E00,
        last    = 0x00462FFF},
    BatteryChargeStatus = {
        command = 0x51000200,
        first   = 0x00295A00,
        last    = 0x00295AFF},
    BatteryInfo = {
        command = 0x51000200,
        first   = 0x00491E00,
        last    = 0x00495DFF},
    InverterTemperature = {
        command = 0x52000200,
        first   = 0x00237700,
        last    = 0x002377FF},
    sbftest = {
        command = 0x64020200,
        first   = 0x00618C00,
        last    = 0x00618FFF}
}

-- '?' is used to indicate the data value is not numeric and may require further processing to extract the embodied info
local RECORD_TYPES = {
    [0x2148] = {str = 'OperationHealth',                recSize = 40, div = 1,    units =  '?'},   -- *08* Condition (aka INV_STATUS)
    [0x2377] = {str = 'CoolsysTmpNom',                  recSize = 28, div = 100,  units =  'C'},   -- *40* Operating condition temperatures
    [0x251E] = {str = 'DcMsWatt',                       recSize = 28, div = 1,    units =  'W'},   -- *40* DC power input (aka SPOT_PDC1 / SPOT_PDC2)
    [0x2601] = {str = 'MeteringTotWhOut',               recSize = 16, div = 1000, units = 'kWh'},   -- *00* Total yield (aka SPOT_ETOTAL)
    [0x2622] = {str = 'MeteringDyWhOut',                recSize = 16, div = 1000, units = 'kWh'},  -- *00* Day yield (aka SPOT_ETODAY)
    [0x263F] = {str = 'GridMsTotW',                     recSize = 28, div = 1,    units =  'W'},   -- *40* Power (aka SPOT_PACTOT)
    [0x295A] = {str = 'BatChaStt',                      recSize = 28, div = 1,    units =  '?'},   -- *00* Current battery charge status
    [0x411E] = {str = 'OperationHealthSttOk ',          recSize = 28, div = 1,    units =  'W'},   -- *00* Nominal power in Ok Mode (aka INV_PACMAX1)
    [0x411F] = {str = 'OperationHealthSttWrn',          recSize = 28, div = 1,    units =  'W'},   -- *00* Nominal power in Warning Mode (aka INV_PACMAX2)
    [0x4120] = {str = 'OperationHealthSttAlm',          recSize = 28, div = 1,    units =  'W'},   -- *00* Nominal power in Fault Mode (aka INV_PACMAX3)
    [0x4164] = {str = 'OperationGriSwStt',              recSize = 40, div = 1,    units =  '?'},   -- *08* Grid relay/contactor (aka INV_GRIDRELAY)
    [0x4166] = {str = 'OperationRmgTms',                recSize = 28, div = 1000, units =  '?'},   -- *00* Waiting time until feed-in
    [0x451F] = {str = 'DcMsVol',                        recSize = 28, div = 100,  units =  'V'},   -- *40* DC voltage input (aka SPOT_UDC1 / SPOT_UDC2)
    [0x4521] = {str = 'DcMsAmp',                        recSize = 28, div = 1000, units =  'A'},   -- *40* DC current input (aka SPOT_IDC1 / SPOT_IDC2)
    [0x4623] = {str = 'MeteringPvMsTotWhOut',           recSize = 28, div = 1000, units =  'c'},   -- *00* PV generation counter reading
    [0x4624] = {str = 'MeteringGridMsTotWhOut',         recSize = 28, div = 1000, units =  'c'},   -- *00* Grid feed-in counter reading
    [0x4625] = {str = 'MeteringGridMsTotWhIn',          recSize = 28, div = 1000, units =  'c'},   -- *00* Grid reference counter reading
    [0x4626] = {str = 'MeteringCsmpTotWhIn',            recSize = 28, div = 1000, units = 'Wh'},   -- *00* Meter reading consumption meter
    [0x4627] = {str = 'MeteringGridMsDyWhOut',          recSize = 28, div = 1000, units = 'Wh'},   -- *00* ?
    [0x4628] = {str = 'MeteringGridMsDyWhIn',           recSize = 28, div = 1000, units = 'Wh'},   -- *00* ?
    [0x462E] = {str = 'MeteringTotOpTms',               recSize = 16, div = 3600, units = 'ms'},   -- *00* Operating time (aka SPOT_OPERTM)
    [0x462F] = {str = 'MeteringTotFeedTms',             recSize = 16, div = 3600, units = 'ms'},   -- *00* Feed-in time (aka SPOT_FEEDTM)
    [0x4631] = {str = 'MeteringGriFailTms',             recSize = 28, div = 3600, units =  '?'},   -- *00* Power outage
    [0x463A] = {str = 'MeteringWhIn',                   recSize = 28, div = 1000, units = 'Wh'},   -- *00* Absorbed energy
    [0x463B] = {str = 'MeteringWhOut',                  recSize = 16, div = 1000, units = 'Wh'},   -- *00* Released energy
    [0x4635] = {str = 'MeteringPvMsTotWOut',            recSize = 28, div = 1000, units = 'Wh'},   -- *40* PV power generated
    [0x4636] = {str = 'MeteringGridMsTotWOut',          recSize = 28, div = 1000, units =  'W'},   -- *40* Power grid feed-in
    [0x4637] = {str = 'MeteringGridMsTotWIn',           recSize = 28, div = 1000, units =  'W'},   -- *40* Power grid reference
    [0x4639] = {str = 'MeteringCsmpTotWIn',             recSize = 28, div = 1000, units =  'W'},   -- *40* Consumer power
    [0x4640] = {str = 'GridMsWphsA',                    recSize = 28, div = 1,    units =  'W'},   -- *40* Power L1 (aka SPOT_PAC1)
    [0x4641] = {str = 'GridMsWphsB',                    recSize = 28, div = 1,    units =  'W'},   -- *40* Power L2 (aka SPOT_PAC2)
    [0x4642] = {str = 'GridMsWphsC',                    recSize = 28, div = 1,    units =  'W'},   -- *40* Power L3 (aka SPOT_PAC3)
    [0x4648] = {str = 'GridMsPhVphsA',                  recSize = 28, div = 100,  units =  'V'},   -- *00* Grid voltage phase L1 (aka SPOT_UAC1)
    [0x4649] = {str = 'GridMsPhVphsB',                  recSize = 28, div = 100,  units =  'V'},   -- *00* Grid voltage phase L2 (aka SPOT_UAC2)
    [0x464A] = {str = 'GridMsPhVphsC',                  recSize = 28, div = 100,  units =  'V'},   -- *00* Grid voltage phase L3 (aka SPOT_UAC3)
    [0x4650] = {str = 'GridMsAphsA_1',                  recSize = 28, div = 1000, units =  'I'},   -- *00* Grid current phase L1 (aka SPOT_IAC1)
    [0x4651] = {str = 'GridMsAphsB_1',                  recSize = 28, div = 1000, units =  'I'},   -- *00* Grid current phase L2 (aka SPOT_IAC2)
    [0x4652] = {str = 'GridMsAphsC_1',                  recSize = 28, div = 1000, units =  'I'},   -- *00* Grid current phase L3 (aka SPOT_IAC3)
    [0x4653] = {str = 'GridMsAphsA',                    recSize = 28, div = 1000, units =  'I'},   -- *00* Grid current phase L1 (aka SPOT_IAC1_2)
    [0x4654] = {str = 'GridMsAphsB',                    recSize = 28, div = 1000, units =  'I'},   -- *00* Grid current phase L2 (aka SPOT_IAC2_2)
    [0x4655] = {str = 'GridMsAphsC',                    recSize = 28, div = 1000, units =  'I'},   -- *00* Grid current phase L3 (aka SPOT_IAC3_2)
    [0x4657] = {str = 'GridMsHz',                       recSize = 28, div = 100,  units = 'Hz'},   -- *00* Grid frequency (aka SPOT_FREQ)
    [0x46AA] = {str = 'MeteringSelfCsmpSelfCsmpWh',     recSize = 28, div = 1000, units = 'Wh'},   -- *00* Energy consumed internally
    [0x46AB] = {str = 'MeteringSelfCsmpActlSelfCsmp',   recSize = 28, div = 1000, units =  'I'},   -- *00* Current self-consumption
    [0x46AC] = {str = 'MeteringSelfCsmpSelfCsmpInc',    recSize = 28, div = 1000, units =  'I'},   -- *00* Current rise in self-consumption
    [0x46AD] = {str = 'MeteringSelfCsmpAbsSelfCsmpInc', recSize = 28, div = 1000, units =  'I'},   -- *00* Rise in self-consumption
    [0x46AE] = {str = 'MeteringSelfCsmpDySelfCsmpInc',  recSize = 28, div = 1000, units =  'I'},   -- *00* Rise in self-consumption today
    [0x491E] = {str = 'BatDiagCapacThrpCnt',            recSize = 28, div = 1,    units =  'c'},   -- *40* Number of battery charge throughputs
    [0x4926] = {str = 'BatDiagTotAhIn',                 recSize = 28, div = 1,    units = 'Ah'},   -- *00* Amp hours counter for battery charge
    [0x4927] = {str = 'BatDiagTotAhOut',                recSize = 28, div = 1,    units = 'Ah'},   -- *00* Amp hours counter for battery discharge
    [0x495B] = {str = 'BatTmpVal',                      recSize = 28, div = 1,    units =  'C'},   -- *40* Battery temperature
    [0x495C] = {str = 'BatVol',                         recSize = 28, div = 1,    units =  'V'},   -- *40* Battery voltage
    [0x495D] = {str = 'BatAmp',                         recSize = 28, div = 1000, units =  'I'},   -- *40* Battery current
    [0x821E] = {str = 'NameplateLocation',              recSize = 40, div = 1,    units =  '?'},   -- *10* Device name (aka INV_NAME)
    [0x821F] = {str = 'NameplateMainModel',             recSize = 40, div = 1,    units =  '?'},   -- *08* Device class (aka INV_CLASS)
    [0x8220] = {str = 'NameplateModel',                 recSize = 40, div = 1,    units =  '?'},   -- *08* Device type (aka INV_TYPE)
    [0x8221] = {str = 'NameplateAvalGrpUsr',            recSize = 28, div = 1,    units =  '?'},   -- *  * Unknown
    [0x8234] = {str = 'NameplatePkgRev',                recSize = 40, div = 1,    units =  '?'},   -- *08* Software package (aka INV_SWVER)
    [0x832A] = {str = 'InverterWLim',                   recSize = 28, div = 1,    units =  'W'},   -- *00* Maximum active power device (aka INV_PACMAX1_2) (Some inverters like SB3300/SB1200)
    [0x464B] = {str = 'GridMsPhVphsA2B6100',            recSize = 28, div = 1000, units =  'V'},
    [0x464C] = {str = 'GridMsPhVphsB2C6100',            recSize = 28, div = 1000, units =  'V'},
    [0x464D] = {str = 'GridMsPhVphsC2A6100',            recSize = 28, div = 1000, units =  'V'}
}

-- http://bitop.luajit.org/api.html
local bitFunctions = require('bit')

-- http://w3.impa.br/~diego/software/luasocket/reference.html
local socket = require('socket')
local http   = require('socket.http')
local ltn12  = require('ltn12')

-- don't change this, it won't do anything. Use the debugEnabled flag instead
local DEBUG_MODE = false

local function debug(textParm, logLevel)
    if DEBUG_MODE then
        local text = ''
        local theType = type(textParm)
        if (theType == 'string') then
            text = textParm
        else
            text = 'type = '..theType..', value = '..tostring(textParm)
        end
        luup.log(PLUGIN_NAME..' debug: '..text,50)

    elseif (logLevel) then
        local text = ''
        if (type(textParm) == 'string') then text = textParm end
        luup.log(PLUGIN_NAME..' debug: '..text, logLevel)
    end
end

-- If non existent, create the variable
-- Update the variable only if needs to be
local function updateVariable(varK, varV, sid, id)
    if (sid == nil) then sid = PLUGIN_SID      end
    if (id  == nil) then  id = THIS_LUL_DEVICE end

    if ((varK == nil) or (varV == nil)) then
        luup.log(PLUGIN_NAME..' debug: '..'Error: updateVariable was supplied with a nil value', 1)
        return
    end

    local newValue = tostring(varV)
    --debug(varK..' = '..newValue)
    debug(newValue..' --> '..varK)

    local currentValue = luup.variable_get(sid, varK, id)
    if ((currentValue ~= newValue) or (currentValue == nil)) then
        luup.variable_set(sid, varK, newValue, id)
    end
end

-- refer also to: http://w3.impa.br/~diego/software/luasocket/http.html
local function urlRequest(request_body)
    http.TIMEOUT = 2  -- using 1 second resulted in timeouts

    local response_body = {}

    -- site not found: r is nil, c is the error status eg (as a string) 'No route to host' and h is nil
    -- site is found:  r is 1, c is the return status (as a number) and h are the returned headers in a table variable
    local r, c, h = http.request {
          url = 'http://pvoutput.org/service/r2/addstatus.jsp',
          method = 'POST',
          headers = {
            ['X-Pvoutput-Apikey']   = m_PVOutputApiKey,
            ['X-Pvoutput-SystemId'] = m_PVOutputSystemID,
            ['Content-Type']        = 'application/x-www-form-urlencoded',
            ['Content-Length']      = string.len(request_body)
          },
          source = ltn12.source.string(request_body),
          sink   = ltn12.sink.table(response_body)
    }

    debug('URL request result: r = '..tostring(r))
    debug('URL request result: c = '..tostring(c))
    debug('URL request result: h = '..tostring(h))

    local page = ''
	if (r == nil) then return false, page end

    if ((c == 200) and (type(response_body) == 'table')) then
        page = table.concat(response_body)
        debug('Returned web page says: '..page)
		return true, page
    end

    if (c == 400) then
        page = table.concat(response_body)
        debug('HTTP 400 Bad Request: invalid data probably sent by the '..PLUGIN_NAME..' plugin', 1)
        debug('Returned web page says: '..page)
        return false, page
    end

    if (c == 401) then
        debug('HTTP 401 Unauthorized: check PVOutput APIkey and SystemID', 1)
        return false, page
    end

    return false, page
end

-- sends the solar data to PVOutput.org
-- see http://pvoutput.org/help.html#api-addstatus
local function addStatusService(energyGeneration, powerGeneration)

    -- abandon all hope if the API key and solar system ID have not been provided
    if ((m_PVOutputApiKey == '') or (m_PVOutputSystemID == '')) then return end

    local energyGeneration = luup.variable_get(PLUGIN_SID,       'kWhToday', THIS_LUL_DEVICE)
    local powerGeneration  = luup.variable_get(ENERGY_METER_SID, 'Watts',    THIS_LUL_DEVICE)

    debug (energyGeneration)
    debug (powerGeneration)

    -- make sure we have the values to be sent to PVOuput.org available
    if ((tonumber(energyGeneration) == nil) or (tonumber(powerGeneration) == nil)) then return end

    -- convert kW to Watts
    energyGeneration = tonumber(energyGeneration) * 1000
    energyGeneration = tostring(energyGeneration)

    local theDate = os.date ('%Y%m%d')
    -- format as 'H:M'
    local theTime = os.date ('%H%%3A%M')

    debug (theDate)
    debug (theTime)

    -- URL encode as needed
    local strTab = {
        'd='  ..theDate,
        't='  ..theTime,
        'v1=' ..energyGeneration,
        'v2=' ..powerGeneration
        --'v5=' ..currentOutsideTemp
    }
    local str = table.concat(strTab,'&')
    debug (str)

    urlRequest(str)
end

-- log the outcome (hex) - only used for testing
local function stringDump(userMsg, str)
    if (not DEBUG_MODE) then return end

    if (str == nil) then debug(userMsg..'is nil') return end
    local strLen = str:len()
    --debug('Length = '..tostring(strLen))

    local hex = ''
    local asc = ''
    local hexTab = {}
    local ascTab = {'   '}
    local dmpTab = {userMsg..'\n\n'}

    for i=1, strLen do
        local ord = str:byte(i)
        hex = string.format("%02X", ord)
        asc = '.'
        if ((ord >= 32) and (ord <= 126)) then asc = string.char(ord) end

        table.insert(hexTab, hex)
        table.insert(ascTab, asc)

        if ((i % 16 == 0) or (i == strLen))then
            table.insert(ascTab,'\n')
            table.insert(dmpTab,table.concat(hexTab, ' '))
            table.insert(dmpTab,table.concat(ascTab))
            hexTab = {}
            ascTab = {'   '}
        elseif (i % 8 == 0) then
            table.insert(hexTab, '')
            table.insert(ascTab, '')
        end
    end

    debug(table.concat(dmpTab))
end

-- replace char in string function
local function replaceChar(pos, str, r)
    return str:sub(1, pos-1) .. r .. str:sub(pos+1)
end

-- string to bytes
local function smaWriteString(strIn)
    local strTab = {}
    for i=1, strIn:len() do
        -- BUG in original code:  smaWriteByte(strIn:sub(i, i+1))
        table.insert(strTab, strIn:sub(i, i))
    end
    return table.concat(strTab)
end

-- short to bytes
local function smaWriteShort(v)
    local strTab = {
        string.char(bitFunctions.band(v,0xff)),
        string.char(bitFunctions.band(bitFunctions.rshift(v,8),0xff))
    }
    return table.concat(strTab)
end

-- long to bytes
local function smaWriteLong(v)
    local strTab = {
        string.char(bitFunctions.band(v,0xff)),
        string.char(bitFunctions.band(bitFunctions.rshift(v, 8),0xff)),
        string.char(bitFunctions.band(bitFunctions.rshift(v,16),0xff)),
        string.char(bitFunctions.band(bitFunctions.rshift(v,24),0xff))
    }
    return table.concat(strTab)
end

-- make SMA packet header
local function smaWritePacketHeader()
    local strTab = {
        string.char   (0x53,0x4d,0x41,0x00),  -- 'SMA\0'
        smaWriteLong  (0xa0020400),
        smaWriteLong  (0x01000000),
        string.char   (0x00),
        string.char   (0x00)  -- the packet length is calculated at the end; this is byte 14 = PKT_LEN_POS
    }
    return table.concat(strTab)
end

-- make SMA packet payload
local function smaWritePacket(longwords, ctrl, ctrl2, dstSUSyID, dstSerial)
    local strTab = {
        smaWriteLong  (ETH_L2_SIGNATURE),
        string.char   (longwords),
        -- all bytes after this point are counted as the "packet length"
        -- it equals total byte count minus 20dec expressed in hex

        string.char   (ctrl),
        smaWriteShort (dstSUSyID),
        smaWriteLong  (dstSerial),
        smaWriteShort (ctrl2),
        smaWriteShort (AppSUSyID),
        smaWriteLong  (AppSerial),
        smaWriteShort (ctrl2),
        smaWriteShort (0),
        smaWriteShort (0),
        smaWriteShort (bitFunctions.bor(smaPacketID,0x8000))
    }
    return table.concat(strTab)
end

-- make SMA packet trailer
local function smaWritePacketTrailer()
    return smaWriteLong(0)
end

-- do a multicast to get the SMA ip address
local function getIPaddress()
    local theIPaddress = nil
    local udp = socket.udp()
    if (udp == nil) then
        debug('Socket failure: socket lib missing?',50)
        return theIPaddress
    end
    udp:settimeout(2)

    -- multicast ip address
    local SMA_MULTICAST_IP = '239.12.255.254'

    -- we multicast to get the ip for the inverter
    local multicastPacket = string.char(0x53,0x4d,0x41,0x00,  0x00,0x04,0x02,0xa0,  0xff,0xff,0xff,0xff,  0x00,0x00,0x00,0x20,  0x00,0x00,0x00,0x00)

    local resultTX, errorMsg = udp:sendto(multicastPacket, SMA_MULTICAST_IP, IP_PORT)
    if (resultTX ~= nil) then
        local resultRX, ipOrErrorMsg = udp:receivefrom()
        if (resultRX == nil) then
            debug('Tried multicast: '..ipOrErrorMsg..' Inverter IP address not found. Enter IP address manually.',50)
        else
            debug('Inverter IP address: '..ipOrErrorMsg,50)
            theIPaddress = ipOrErrorMsg
        end
    end

    udp:close()

    return theIPaddress
end

local function logOn(udp)
    -- create session and application ids
    AppSUSyID = 125  -- 0x7d

    math.randomseed(os.time())
    AppSerial = 900000000 + (((bitFunctions.lshift(math.random(1,32767),16)) + math.random(1,32767)) % 100000000)
    debug('AppSerial: '..AppSerial)

    -- User / Installer
    local UG_USER      = 0x00000007
    local UG_INSTALLER = 0x0000000A

    -- UG_USER      is 0x88
    -- UG_INSTALLER is 0xBB

    -- try to log on
    smaPacketID = smaPacketID + 2
    local pwEnc, pwEncChar

    pwEnc = string.char(0x88,0x88,0x88,0x88,0x88,0x88,0x88,0x88,0x88,0x88,0x88,0x88)

    for i=1, string.len(PW_USER) do
        pwEncChar = string.char(string.byte(string.sub(PW_USER,i,i+1)) + 0x88)
        pwEnc = replaceChar(i, pwEnc, pwEncChar)
    end

    --local localTimeIncDST = os.difftime(os.time(),os.time{year = 1970, month = 1, day = 1, hour = 0, sec = 0})
    local localTimeIncDST = os.time()

    -- command: log on, password encrypted
    local strTab = {
        smaWritePacketHeader  (),  -- pckLength = 0x3a
        smaWritePacket        (0x0e, 0xa0, 0x0100, DEST_SUSY_ID, DEST_SERIAL_NUMBER),
        smaWriteLong          (0xfffd040c),
        smaWriteLong          (UG_USER),      -- user_group
        smaWriteLong          (0x00000384),   -- timeout = 900sec ?
        smaWriteLong          (localTimeIncDST),
        smaWriteLong          (0),
        smaWriteString        (pwEnc),
        smaWritePacketTrailer ()
    }
    local passwordPacket = table.concat(strTab)
    passwordPacket = replaceChar(PKT_LEN_POS, passwordPacket, string.char(passwordPacket:len()-PKT_EXCLUDE))
    --stringDump('passwordPacket', passwordPacket)
    local resultTX, errorMsg = udp:sendto(passwordPacket, ipAddress, IP_PORT)
    if (resultTX ~= nil) then
        local resultRX, ipOrErrorMsg = udp:receivefrom()
        --stringDump('Password result', result)
        if (resultRX == nil) then
            debug('No result from inverter for logon: '..ipOrErrorMsg)
        else
            debug('Successfully logged on to: '..ipOrErrorMsg)
        end
    else
        debug('Reply to password is nil: '..errorMsg)
    end
end

local function logOff(udp)
    -- command: log off
    local strTab = {
        smaWritePacketHeader  (),  -- pckLength = 0x22
        smaWritePacket        (0x08, 0xa0, 0x0300, DEST_SUSY_ID, DEST_SERIAL_NUMBER),
        smaWriteLong          (0xfffd010e),
        smaWriteLong          (0xffffffff),
        smaWritePacketTrailer ()
    }
    local cmdLogOffPacket = table.concat(strTab)
    cmdLogOffPacket = replaceChar(PKT_LEN_POS, cmdLogOffPacket, string.char(cmdLogOffPacket:len()-PKT_EXCLUDE))
    --stringDump('cmdLogOffPacket', cmdLogOffPacket)
    local resultTX, errorMsg = udp:sendto(cmdLogOffPacket, ipAddress, IP_PORT)
    debug('Logged off')
end

-- index points to left most byte
local function getLong(str, idx)
    local byte0 = str:byte(idx + 0)
    local byte1 = str:byte(idx + 1)
    local byte2 = str:byte(idx + 2)
    local byte3 = str:byte(idx + 3)

    -- no data comes up as 0xffffffff or 0x80000000
    local longData = nil
    if ((byte0 == 0xff) and (byte1 == 0xff) and (byte2 == 0xff) and (byte3 == 0xff)) then return longData end
    if ((byte0 == 0x00) and (byte1 == 0x00) and (byte2 == 0x00) and (byte3 == 0x80)) then return longData end

    longData = byte3
    longData = bitFunctions.bor(bitFunctions.lshift(longData,8), byte2)
    longData = bitFunctions.bor(bitFunctions.lshift(longData,8), byte1)
    longData = bitFunctions.bor(bitFunctions.lshift(longData,8), byte0)

    return longData
end

-- get the data from the inverter
local function getInverterData(udp, inverterDataType)
    -- set up a command
    local strTab = {
        smaWritePacketHeader  (),  -- pckLength = 0x26
        smaWritePacket        (0x09, 0xe0, 0, DEST_SUSY_ID, DEST_SERIAL_NUMBER),
        smaWriteLong          (inverterDataType.command),
        smaWriteLong          (inverterDataType.first),
        smaWriteLong          (inverterDataType.last),
        smaWritePacketTrailer ()
    }

    local cmdValuesPacket = table.concat(strTab)
    cmdValuesPacket = replaceChar(PKT_LEN_POS, cmdValuesPacket, string.char(cmdValuesPacket:len()-PKT_EXCLUDE))
    --stringDump('cmdValuesPacket', cmdValuesPacket)
    local resultTX, errorMsg = udp:sendto(cmdValuesPacket, ipAddress, IP_PORT)

    if (resultTX ~= nil) then
        local resultRX, ipOrErrorMsg = udp:receivefrom()
        stringDump('Command result RXed: ', resultRX)

        if (resultRX == nil) then
            debug('no result RXed: get values: ', ipOrErrorMsg)
        else
            local recSize  = 0
            local recStart = 55
            local i        = recStart
            debug(string.len(resultRX))

            for i=recStart, string.len(resultRX)-4 do
                local test = resultRX:byte(i)+(resultRX:byte(i+1)*256)+(resultRX:byte(i+2)*256^2)+(resultRX:byte(i+3)*256^3)
                debug('i = ' .. tostring(i) .. '    ' .. tostring(test))
            end

            -- do all the records in the packet
            local timeFormat = '%F %X'
            i = recStart
            while (resultRX:byte(i + 11) ~= nil) do
                local cls      =         resultRX:byte(i + 0)                    -- 55
                local lri      =         resultRX:byte(i + 1)                    -- 56
                               +        (resultRX:byte(i + 2)*256)               -- 57
                local dataType =         resultRX:byte(i + 3)                    -- 58
                local dateTime = getLong(resultRX,     i + 4)  -- and 5,6,7      -- 59, 60, 61, 62
                local value    = getLong(resultRX,     i + 8)  -- and 9,10,11    -- 63, 64, 65, 66

                local currentRec = RECORD_TYPES[lri]

                -- protect against table look up failures - this happens from time to time!
                -- eg:  lri not found in table: lri: 0x00236D00
                if (currentRec == nil) then
                    debug('lri not found in table: lri: 0x00'..string.format('%04X', lri)..'00')
                    debug('dateTime: '..tostring(dateTime)..': '..os.date(timeFormat, dateTime))
                    debug('Possible value follows:')
                    debug(value)
                    break
                end

                recSize = currentRec.recSize

                debug('lri: 0x00'..string.format('%04X', lri)..'00')
                debug('lri: '..currentRec.str)
                debug('cls: 0x'..string.format('%02X', cls))
                debug('recSize: '..tostring(currentRec.recSize))
                debug('dataType: 0x'..string.format('%02X', dataType))
                debug('dateTime: '..tostring(dateTime)..': '..os.date(timeFormat, dateTime))

                if (currentRec.units ~= '?') then -- value is flagged as numeric
                    if (value ~= nil) then
                        -- update our table of results
                        inverterData[currentRec.str] = value/currentRec.div
                        debug('value: '..tostring(inverterData[currentRec.str])..' '..currentRec.units)
                    else
                        debug('value: 0xffffffff or 0x80000000 is assumed to be nil data')
                    end
                --else -- a non numeric value, that needs further processing
                    -- do other stuff
                end

                i = i + recSize
            end
        end
    else
        debug('Reply to command is nil: '..errorMsg)
    end
end

-- do set the inverter time
local function doSetInverterTime(udp)

    local timeUTC  =  os.time()
    local tzOffset = -os.time({year = 1970, month = 1, day = 1, hour = 0, sec = 0})

    local timeFormat = '%F %X'
    -- this writes as local time
    debug('Time set to: '..tostring(timeUTC)..': '..os.date(timeFormat, timeUTC))
    debug('Time zone/offset set to: '..tostring(tzOffset/3600)..' hours')

    -- command: set inverter time
    local strTab = {
        smaWritePacketHeader  (),  -- pckLength = 0x42
        smaWritePacket        (0x10, 0xa0, 0x0, DEST_SUSY_ID, DEST_SERIAL_NUMBER),
        smaWriteLong          (0xf000020a),
        smaWriteLong          (0x00236d00),
        smaWriteLong          (0x00236d00),
        smaWriteLong          (0x00236d00),
        smaWriteLong          (timeUTC),
        smaWriteLong          (timeUTC),
        smaWriteLong          (timeUTC),
        smaWriteLong          (tzOffset),
        smaWriteLong          (0x1),
        smaWriteLong          (0x1),
        smaWritePacketTrailer ()
    }

    local cmdSetInverterTimePacket = table.concat(strTab)
    cmdSetInverterTimePacket = replaceChar(PKT_LEN_POS, cmdSetInverterTimePacket, string.char(cmdSetInverterTimePacket:len()-PKT_EXCLUDE))
    stringDump('cmdSetInverterTimePacket', cmdSetInverterTimePacket)
    local resultTX, errorMsg = udp:sendto(cmdSetInverterTimePacket, ipAddress, IP_PORT)
    -- the inverter appears not to send any response message at this point
end

local function getInverterInfo(udp)
    if (m_first_time) then
        --doSetInverterTime(udp)  -- HACK used during testing
        m_first_time = false
    end

    getInverterData(udp, COMMANDS.EnergyProduction)
    getInverterData(udp, COMMANDS.SpotACTotalPower)
    getInverterData(udp, COMMANDS.InverterTemperature)

    --testing: try out some other commands
    --getInverterData(udp, COMMANDS.SpotACPower)
    --getInverterData(udp, COMMANDS.SpotDCVoltage)
    --getInverterData(udp, COMMANDS.SpotDCPower)
    --getInverterData(udp, COMMANDS.SpotACVoltage)
    --getInverterData(udp, COMMANDS.SpotGridFrequency)
    --getInverterData(udp, COMMANDS.TypeLabel)

    for k, v in pairs(inverterData) do
        debug(k..': '..tostring(v))
    end
end

-- Poll the inverter for data
-- function needs to be global
function pollInverter()
    if (m_PollEnable ~= '1') then return end

    -- it's a solar inverter, not a lunar inverter
    if (luup.is_night()) then
        luup.call_delay('pollInverter', m_PollInterval)
        return
    end

    local udp = socket.udp()
    udp:settimeout(2)
    logOn(udp)
    getInverterInfo(udp)
    logOff(udp)
    udp:close()

    updateVariable('InverterTemp', inverterData.CoolsysTmpNom,    TEMP_SENSOR_SID)
    updateVariable('Watts',        inverterData.GridMsTotW,       ENERGY_METER_SID)
    updateVariable('KWH',          inverterData.MeteringTotWhOut, ENERGY_METER_SID)
    updateVariable('kWhToday',     inverterData.MeteringDyWhOut)


    local timeStamp = os.time()
    updateVariable('LastUpdate', timeStamp, HA_SID)
    updateVariable('KWHReading', timeStamp, ENERGY_METER_SID)

    local timeFormat = '%F %X'
    debug('Last update: '..os.date(timeFormat, timeStamp))

    timeFormat = '%H:%M'
    updateVariable('LastUpdateHr', os.date(timeFormat, timeStamp))

    -- send to PVOutput.org if the API key and System ID are available
    addStatusService(inverterData.MeteringDyWhOut, inverterData.GridMsTotW)

    -- get the inverter info every poll interval
    luup.call_delay('pollInverter', m_PollInterval)
end

-- User service: polling on off
-- function needs to be global
local function polling(pollEnable)
    if (not ((pollEnable == '0') or (pollEnable == '1'))) then return end
    m_PollEnable = pollEnable
    updateVariable('PollEnable', m_PollEnable)
end

-- User service: set the inverter time
local function setInverterTime()
    local udp = socket.udp()
    udp:settimeout(2)
    logOn(udp)
    doSetInverterTime(udp)
    logOff(udp)
    udp:close()
end

function luaStartUp(lul_device)
    THIS_LUL_DEVICE = lul_device
    debug('Initialising plugin: '..PLUGIN_NAME)

    -- Lua ver 5.1 does not have bit functions, whereas ver 5.2 and above do
    debug('Using: '.._VERSION)

    if (bitFunctions == nil) then
        debug('Bit library not found',1)
        return false, 'Bit library not found', PLUGIN_NAME
    end

    -- set up some defaults:
    updateVariable('PluginVersion', PLUGIN_VERSION)

    local debugEnabled = luup.variable_get(PLUGIN_SID, 'DebugEnabled', THIS_LUL_DEVICE)
    if ((debugEnabled == nil) or (debugEnabled == '')) then
	    debugEnabled = '0'
        updateVariable('DebugEnabled', debugEnabled)
    end
	DEBUG_MODE = (debugEnabled == '1')

    local pluginEnabled    = luup.variable_get(PLUGIN_SID,       'PluginEnabled',    THIS_LUL_DEVICE)
    local pollEnable       = luup.variable_get(PLUGIN_SID,       'PollEnable',       THIS_LUL_DEVICE)
    local pollInterval     = luup.variable_get(PLUGIN_SID,       'PollInterval',     THIS_LUL_DEVICE)
    local watts            = luup.variable_get(ENERGY_METER_SID, 'Watts',            THIS_LUL_DEVICE)
    local kWh              = luup.variable_get(ENERGY_METER_SID, 'KWH',              THIS_LUL_DEVICE)
    local kWhToday         = luup.variable_get(PLUGIN_SID,       'kWhToday',         THIS_LUL_DEVICE)
    local pvOutputApiKey   = luup.variable_get(PLUGIN_SID,       'PVOutputApiKey',   THIS_LUL_DEVICE)
    local pvOutputSystemID = luup.variable_get(PLUGIN_SID,       'PVOutputSystemID', THIS_LUL_DEVICE)

    if ((pluginEnabled == nil) or (pluginEnabled == '')) then
	    pluginEnabled = '1'
        updateVariable('PluginEnabled', pluginEnabled)
    end

    if ((pollEnable == nil) or (pollEnable == '')) then
        -- turn the polling on
        m_PollEnable = '1'
        polling(m_PollEnable)
    else
        m_PollEnable = pollEnable
    end

    -- don't allow polling any faster than five minutes
    local theInterval = tonumber(pollInterval)
    if ((theInterval == nil) or (theInterval < FIVE_MIN_IN_SECS)) then
        m_PollInterval = FIVE_MIN_IN_SECS
        updateVariable('PollInterval', tostring(FIVE_MIN_IN_SECS))
    else
        m_PollInterval = theInterval
    end

    -- The user must enter an API key
    if ((pvOutputApiKey == nil) or (pvOutputApiKey == '')) then
        -- first time round, this will create the variable but
        -- it remains invalid; the user must set it
        m_PVOutputApiKey = ''
        luup.variable_set(PLUGIN_SID, 'PVOutputApiKey', m_PVOutputApiKey, THIS_LUL_DEVICE)
    else
        m_PVOutputApiKey = pvOutputApiKey
    end

    -- The user must enter an solar PV system ID. The ID is a numeric string. The SystemID is a numeric string,
    -- which identifies a system. The SystemID can be obtained from the Settings page under Registered Systems.
    if ((pvOutputSystemID == nil) or (pvOutputSystemID == '')) then
        -- first time round, this will create the variable but
        -- it remains invalid; the user must set it
        m_PVOutputSystemID = ''
        luup.variable_set(PLUGIN_SID, 'PVOutputSystemID', m_PVOutputSystemID, THIS_LUL_DEVICE)
    else
        m_PVOutputSystemID = pvOutputSystemID
    end

    if (pluginEnabled ~= '1') then return true, 'All OK', PLUGIN_NAME end

    -- The ip address can be usually be found using a multicast but not
    -- always. If found, it will be the correct address at any one time.
    ipAddress = getIPaddress()
    -- we'll also check what's currently stored
    local ipa = luup.devices[THIS_LUL_DEVICE].ip
    if ((ipAddress == nil) or (ipAddress == '')) then
        -- Multicast has failed. See if there is an automatically determined
        -- or manually entered address available from previous a run.
        ipAddress = ipa:match('^(%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?)')
        if ((ipAddress == nil) or (ipAddress == '')) then
            -- We failed to get a valid ip address. The user will need to enter one.
            return false, 'Multicast failed: manually enter IP address', PLUGIN_NAME
        end
    else -- multicast succeeded
        if (ipa ~= ipAddress) then
            -- if it's not already saved, save the address
            luup.attr_set('ip', ipAddress, THIS_LUL_DEVICE)
        end
    end

    -- required for UI7
    luup.set_failure(false)

    -- delay so that the first poll occurs delay interval after start up
    local INITIAL_POLL_INTERVAL_SECS = 65
    luup.call_delay('pollInverter', INITIAL_POLL_INTERVAL_SECS)

    return true, 'All OK', PLUGIN_NAME
end

--luaStartUp(nil)

--return true

--[[

https://translate.googleusercontent.com/translate_c?depth=1&hl=en&prev=search&rurl=translate.google.com.au&sl=de&u=https://gist.github.com/hdo/6027504&usg=ALkJrhjpWEFQZtjxZKWT4seteeZsfkrLGA

https://translate.google.com.au/translate?hl=en&sl=de&u=http://www.eb-systeme.de/%3Fpage_id%3D1240&prev=search

https://github.com/rhuss/net-bluetooth-sunny/blob/master/Net/Bluetooth/Sunny.pm

https://github.com/stuartpittaway/nanodesmapvmonitor/blob/master/nanodesmapvmonitor.ino

                                                              model??
                           SMA       fixed              count   fixed             dest_address    ctrl2      srcaddress ctrl2 fixed    pktID  cmd_reg   parms     payload
cmd_login               = '534d4100  000402a0  00000001 00  3a  00106065  0e  a0  ffff  ffffffff  0001  7800  %s        0001  00000000  0480  0c 04fd ff  07000000  84030000  4c20cb5100000000%s   00000000' % (struct.pack('<I', src_serial).encode('hex'), get_encoded_pw(user_pw))
cmd_logout              = '534d4100  000402a0  00000001 00  22  00106065  08  a0  ffff  ffffffff  0003  7800  %s        0003  00000000  d784  0e 01fd ff  ffffffff  00000000  '         % (struct.pack('<I', src_serial).encode('hex'))
cmd_query_total_today   = '534d4100  000402a0  00000001 00  26  00106065  09  e0  b500  %s        0000  7800  %s        0000  00000000  f1b1  00 0200 54  00002600  ffff2600  00000000' % (struct.pack('<I', dst_serial).encode('hex'), struct.pack('<I', src_serial).encode('hex'))
cmd_query_spot_ac_power = '534d4100  000402a0  00000001 00  26  00106065  09  e0  b500  %s        0000  7800  %s        0000  00000000  81f0  00 0200 51  00002600  ffff2600  00000000' % (struct.pack('<I', dst_serial).encode('hex'), struct.pack('<I', src_serial).encode('hex'))

]]

--[[
An example of SMA data produced by the SBFspot program:   http://sbfspot.codeplex.com/

Connecting to 00:80:25:24:9B:1B (1/10)
Initializing...
SUSyID: 125 - SN: 852675450 (0x32D2CB7A)
SMA netID=01
Serial Nr: 7756B1F6 (2002170358)
BT Signal=69%
Logon OK
Local Time: 23/09/2014 13:51:35
TZ offset (s): 0 - DST: Off

SUSyID: 99 - SN: 2002170358
Device Name: SN: 2002170358
Device Class: Solar Inverters
Device Type: SB 1600TL-10
Software Version: 12.12.208.R
Serial number: 2002170358

SUSyID: 99 - SN: 2002170358
Device Status: Ok

SUSyID: 99 - SN: 2002170358
Device Temperature: 0.0°C

SUSyID: 99 - SN: 2002170358
GridRelay Status: ?

SUSyID: 99 - SN: 2002170358
Pac max phase 1: 1600W
Pac max phase 2: 0W
Pac max phase 3: 0W

SUSyID: 99 - SN: 2002170358
Energy Production:
EToday: 2.050kWh
ETotal: 3585.376kWh
Operation Time: 10319.38h
Feed-In Time : 8355.91h

SUSyID: 99 - SN: 2002170358
DC Spot Data:
String 1 Pdc: 0.296kW - Udc: 175.00V - Idc: 1.695A
String 2 Pdc: 0.000kW - Udc: 0.00V - Idc: 0.000A

SUSyID: 99 - SN: 2002170358
AC Spot Data:
Phase 1 Pac : 0.000kW - Uac: 234.30V - Iac: 0.000A
Phase 2 Pac : 0.000kW - Uac: 0.00V - Iac: 0.000A
Phase 3 Pac : 0.000kW - Uac: 0.00V - Iac: 0.000A
Total Pac : 0.272kW

SUSyID: 99 - SN: 2002170358
Grid Freq. : 49.96Hz

SUSyID: 99 - SN: 2002170358
Current Inverter Time: 23/09/2014 13:51:54
Inverter Wake-Up Time: 23/09/2014 13:51:54
Inverter Sleep Time : 23/09/2014 13:51:55

]]

