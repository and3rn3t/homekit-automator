# Device Categories and Characteristics Reference

Complete reference for all HomeKit accessory categories supported by HomeKit Automator,
including every controllable and readable characteristic.

## Table of Contents

1. [Lights](#lights)
2. [Thermostats](#thermostats)
3. [Locks](#locks)
4. [Doors](#doors)
5. [Garage Doors](#garage-doors)
6. [Fans](#fans)
7. [Window Coverings](#window-coverings)
8. [Switches](#switches)
9. [Outlets](#outlets)
10. [Sensors](#sensors)
11. [Characteristic Type Reference](#characteristic-type-reference)

## Lights

**Category name:** `light`
**HomeKit type:** `HMAccessoryCategoryTypeLightbulb`

| Characteristic | Type | Range | Writable | Description |
|---------------|------|-------|----------|-------------|
| `power` | Boolean | true/false | Yes | Turn light on or off |
| `brightness` | Integer | 0–100 | Yes | Brightness percentage |
| `hue` | Float | 0–360 | Yes | Color hue in degrees (0=red, 120=green, 240=blue) |
| `saturation` | Float | 0–100 | Yes | Color saturation percentage (0=white, 100=fully saturated) |
| `colorTemperature` | Integer | 140–500 | Yes | Color temperature in mireds (140=cool/blue, 500=warm/yellow) |

**Notes:**
- Not all lights support all characteristics. A basic on/off bulb may only have `power`.
- Dimmable lights add `brightness`. Color lights add `hue` and `saturation`.
- Color temperature lights (e.g., warm-to-cool white) use `colorTemperature` instead of `hue`/`saturation`.
- Setting `hue`/`saturation` on a light that only supports `colorTemperature` will fail.
- Mireds = 1,000,000 / Kelvin. So 140 mireds ≈ 7143K (daylight), 500 mireds ≈ 2000K (candlelight).

**Common commands:**
```
homekitauto set "Kitchen Lights" power on
homekitauto set "Kitchen Lights" brightness 60
homekitauto set "Bedroom Lamp" colorTemperature 350   # Warm white
homekitauto set "Living Room Strip" hue 240            # Blue
homekitauto set "Living Room Strip" saturation 100     # Fully saturated
```

## Thermostats

**Category name:** `thermostat`
**HomeKit type:** `HMAccessoryCategoryTypeThermostat`

| Characteristic | Type | Range | Writable | Description |
|---------------|------|-------|----------|-------------|
| `targetTemperature` | Float | 10–38 (°C) or 50–100 (°F) | Yes | Desired temperature |
| `currentTemperature` | Float | — | **No** | Current ambient temperature reading |
| `hvacMode` | Integer | 0–3 | Yes | 0=off, 1=heat, 2=cool, 3=auto |
| `currentHeatingCoolingState` | Integer | — | **No** | 0=off, 1=heating, 2=cooling |
| `targetHumidity` | Float | 0–100 | Yes | Desired relative humidity (if supported) |
| `currentHumidity` | Float | — | **No** | Current relative humidity reading |

**Notes:**
- Temperature ranges vary by device and region. The HomeKit API reports values in Celsius. The skill converts to Fahrenheit based on the user's locale.
- `currentTemperature` and `currentHeatingCoolingState` are read-only sensor readings.
- Not all thermostats support humidity control. Check the device's characteristics.
- `hvacMode` accepts string aliases: "off", "heat", "cool", "auto".

**Common commands:**
```
homekitauto set "Thermostat" targetTemperature 72
homekitauto set "Thermostat" hvacMode heat
homekitauto get "Thermostat"    # Shows both current and target temps
```

## Locks

**Category name:** `lock`
**HomeKit type:** `HMAccessoryCategoryTypeDoorLock`

| Characteristic | Type | Range | Writable | Description |
|---------------|------|-------|----------|-------------|
| `lockState` | Integer | 0–3 | Yes | 0=unsecured (unlocked), 1=secured (locked) |
| `currentLockState` | Integer | — | **No** | 0=unsecured, 1=secured, 2=jammed, 3=unknown |

**Notes:**
- `lockState` is the target (what you want). `currentLockState` is the actual state (what it is now).
- A jammed state (2) means the lock motor couldn't complete the operation.
- String aliases accepted: "locked"/"unlocked" or "on"/"off" or "true"/"false".

**Common commands:**
```
homekitauto set "Front Door Lock" lockState locked
homekitauto set "Front Door Lock" lockState unlocked
homekitauto get "Front Door Lock"    # Shows current and target state
```

## Doors

**Category name:** `door`
**HomeKit type:** `HMAccessoryCategoryTypeDoor`

| Characteristic | Type | Range | Writable | Description |
|---------------|------|-------|----------|-------------|
| `targetPosition` | Integer | 0–100 | Yes | Target position (0=closed, 100=open) |
| `currentPosition` | Integer | — | **No** | Current position |
| `positionState` | Integer | — | **No** | 0=going to minimum, 1=going to maximum, 2=stopped |

**Common commands:**
```
homekitauto set "Front Door" targetPosition 0     # Close
homekitauto set "Front Door" targetPosition 100   # Open
```

## Garage Doors

**Category name:** `garageDoor`
**HomeKit type:** `HMAccessoryCategoryTypeGarageDoorOpener`

| Characteristic | Type | Range | Writable | Description |
|---------------|------|-------|----------|-------------|
| `targetPosition` | Integer | 0/1 | Yes | 0=open, 1=closed (note: reversed from doors) |
| `currentPosition` | Integer | — | **No** | 0=open, 1=closed, 2=opening, 3=closing, 4=stopped |
| `obstructionDetected` | Boolean | — | **No** | Whether something is blocking the door |

**Notes:**
- Garage door state values are reversed from regular doors (0=open, 1=closed).
- String aliases: "open"/"closed".
- Always check `obstructionDetected` before closing.

**Common commands:**
```
homekitauto set "Garage Door" targetPosition closed
homekitauto set "Garage Door" targetPosition open
homekitauto get "Garage Door"    # Shows current state + obstruction
```

## Fans

**Category name:** `fan`
**HomeKit type:** `HMAccessoryCategoryTypeFan`

| Characteristic | Type | Range | Writable | Description |
|---------------|------|-------|----------|-------------|
| `active` | Boolean | true/false | Yes | Turn fan on or off |
| `rotationSpeed` | Float | 0–100 | Yes | Fan speed percentage |
| `rotationDirection` | Integer | 0/1 | Yes | 0=clockwise, 1=counter-clockwise |
| `swingMode` | Integer | 0/1 | Yes | 0=disabled, 1=enabled (oscillation) |

**Common commands:**
```
homekitauto set "Bedroom Fan" active on
homekitauto set "Bedroom Fan" rotationSpeed 75
homekitauto set "Bedroom Fan" swingMode 1    # Enable oscillation
```

## Window Coverings

**Category name:** `windowCovering`
**HomeKit type:** `HMAccessoryCategoryTypeWindowCovering`

| Characteristic | Type | Range | Writable | Description |
|---------------|------|-------|----------|-------------|
| `targetPosition` | Integer | 0–100 | Yes | Target position (0=closed/down, 100=open/up) |
| `currentPosition` | Integer | — | **No** | Current position |
| `positionState` | Integer | — | **No** | 0=decreasing, 1=increasing, 2=stopped |

**Notes:**
- The meaning of 0 and 100 depends on the specific blind/shade. For most: 0=fully closed, 100=fully open.
- Some motorized blinds take several seconds to reach the target position.

**Common commands:**
```
homekitauto set "Living Room Blinds" targetPosition 50    # Half open
homekitauto set "Bedroom Shades" targetPosition 0         # Fully closed
```

## Switches

**Category name:** `switch`
**HomeKit type:** `HMAccessoryCategoryTypeSwitch`

| Characteristic | Type | Range | Writable | Description |
|---------------|------|-------|----------|-------------|
| `power` | Boolean | true/false | Yes | On or off |

**Common commands:**
```
homekitauto set "Coffee Maker Switch" power on
```

## Outlets

**Category name:** `outlet`
**HomeKit type:** `HMAccessoryCategoryTypeOutlet`

| Characteristic | Type | Range | Writable | Description |
|---------------|------|-------|----------|-------------|
| `power` | Boolean | true/false | Yes | Outlet on or off |
| `outletInUse` | Boolean | — | **No** | Whether something is drawing power |

**Common commands:**
```
homekitauto set "Desk Outlet" power off
homekitauto get "Desk Outlet"    # Shows power state + whether in use
```

## Sensors

**Category name:** `sensor`
**HomeKit type:** `HMAccessoryCategoryTypeSensor`

All sensor characteristics are **read-only**. Sensors report data but cannot be controlled.

| Characteristic | Type | Sensor Type | Description |
|---------------|------|-------------|-------------|
| `motionDetected` | Boolean | Motion sensor | Whether motion is currently detected |
| `contactState` | Integer | Contact sensor | 0=detected (closed), 1=not detected (open) |
| `currentTemperature` | Float | Temperature sensor | Temperature reading in °C |
| `currentHumidity` | Float | Humidity sensor | Relative humidity percentage |
| `lightLevel` | Float | Light sensor | Ambient light level in lux |
| `batteryLevel` | Integer | Any battery-powered sensor | Battery percentage (0–100) |

**Notes:**
- Sensors cannot be "set" — they only report values.
- Motion sensors return to `false` after a timeout period (varies by device, typically 30–60 seconds).
- Contact sensors are commonly used on doors and windows. "Detected" (0) means the magnet is aligned (door closed).
- Battery level is reported by any HomeKit accessory with a battery, not just dedicated sensors.

**Common commands:**
```
homekitauto get "Hallway Motion Sensor"
homekitauto get "Front Door Contact Sensor"
homekitauto get "Outdoor Temperature Sensor"
```

## Characteristic Type Reference

Quick lookup table for all characteristic friendly names used in commands:

| Friendly Name | HomeKit Constant | Category | R/W |
|--------------|-----------------|----------|-----|
| `power` | `HMCharacteristicTypePowerState` | Lights, Switches, Outlets | RW |
| `brightness` | `HMCharacteristicTypeBrightness` | Lights | RW |
| `hue` | `HMCharacteristicTypeHue` | Color Lights | RW |
| `saturation` | `HMCharacteristicTypeSaturation` | Color Lights | RW |
| `colorTemperature` | `HMCharacteristicTypeColorTemperature` | CT Lights | RW |
| `targetTemperature` | `HMCharacteristicTypeTargetTemperature` | Thermostats | RW |
| `currentTemperature` | `HMCharacteristicTypeCurrentTemperature` | Thermostats, Sensors | RO |
| `hvacMode` | `HMCharacteristicTypeTargetHeatingCooling` | Thermostats | RW |
| `currentHeatingCoolingState` | `HMCharacteristicTypeCurrentHeatingCooling` | Thermostats | RO |
| `lockState` | `HMCharacteristicTypeLockMechanismTargetState` | Locks | RW |
| `currentLockState` | `HMCharacteristicTypeLockMechanismCurrentState` | Locks | RO |
| `targetPosition` | `HMCharacteristicTypeTargetPosition` | Doors, Blinds | RW |
| `currentPosition` | `HMCharacteristicTypeCurrentPosition` | Doors, Blinds | RO |
| `active` | `HMCharacteristicTypeActive` | Fans | RW |
| `rotationSpeed` | `HMCharacteristicTypeRotationSpeed` | Fans | RW |
| `rotationDirection` | `HMCharacteristicTypeRotationDirection` | Fans | RW |
| `swingMode` | `HMCharacteristicTypeSwingMode` | Fans | RW |
| `motionDetected` | `HMCharacteristicTypeMotionDetected` | Motion Sensors | RO |
| `contactState` | `HMCharacteristicTypeContactState` | Contact Sensors | RO |
| `batteryLevel` | `HMCharacteristicTypeBatteryLevel` | Any battery device | RO |
| `targetHumidity` | `HMCharacteristicTypeTargetRelativeHumidity` | Thermostats | RW |
| `currentHumidity` | `HMCharacteristicTypeCurrentRelativeHumidity` | Humidity Sensors | RO |
| `lightLevel` | `HMCharacteristicTypeCurrentLightLevel` | Light Sensors | RO |

**RW** = Read-Write (can be controlled)
**RO** = Read-Only (sensor/status values only)
