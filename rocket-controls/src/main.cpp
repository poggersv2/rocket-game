#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <DHT.h>

// ---------- Pins ----------
#define PIN_SDA     21
#define PIN_SCL     22
#define PIN_FRONT   4
#define PIN_BACK    2
#define PIN_DHT     19

// ---------- Display ----------
#define SCREEN_W    128
#define SCREEN_H    64
#define OLED_ADDR   0x3C

Adafruit_SSD1306 display(SCREEN_W, SCREEN_H, &Wire, -1);
bool oledOk = false;

// ---------- DHT11 ----------
DHT dht(PIN_DHT, DHT11);

float temperature = NAN;
float humidity = NAN;

unsigned long lastDhtRead = 0;
const unsigned long DHT_INTERVAL = 2000;

// ---------- Pages ----------
enum Page {
  PAGE_DHT,
  PAGE_SWITCH,
  PAGE_I2C,
  PAGE_COUNT
};

int currentPage = PAGE_DHT;

// ---------- Button with debounce ----------
struct Button {
  uint8_t pin;
  bool stable = false;
  bool lastRead = false;
  bool pressedEvent = false;
  unsigned long lastChange = 0;

  void begin(uint8_t p) {
    pin = p;
    pinMode(pin, INPUT_PULLUP);

    // Initialise the state from the actual pin
    stable = (digitalRead(pin) == LOW);
    lastRead = stable;
    lastChange = millis();
  }

  void update() {
    bool reading = (digitalRead(pin) == LOW);

    if (reading != lastRead) {
      lastChange = millis();
      lastRead = reading;
    }

    if (millis() - lastChange >= 30 && reading != stable) {
      stable = reading;

      if (stable) {
        pressedEvent = true;
      }
    }
  }

  bool wasPressed() {
    if (pressedEvent) {
      pressedEvent = false;
      return true;
    }

    return false;
  }
};

Button btnFront, btnBack;

// ---------- I2C scan ----------
uint8_t foundAddrs[16];
int foundCount = 0;

void scanI2C() {
  foundCount = 0;

  for (uint8_t addr = 1; addr < 127 && foundCount < 16; addr++) {
    Wire.beginTransmission(addr);

    if (Wire.endTransmission() == 0) {
      foundAddrs[foundCount++] = addr;
    }
  }

  Serial.printf("[I2C] Found %d device(s)\n", foundCount);

  for (int i = 0; i < foundCount; i++) {
    Serial.printf("  Address: 0x%02X\n", foundAddrs[i]);
  }
}

// ---------- Drawing ----------
void drawHeader(const char *title) {
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);

  display.print(title);

  display.setCursor(104, 0);
  display.printf("%d/%d", currentPage + 1, (int)PAGE_COUNT);

  display.drawFastHLine(0, 10, SCREEN_W, SSD1306_WHITE);
}

void drawDhtPage() {
  drawHeader("DHT11");

  display.setTextSize(2);
  display.setCursor(0, 18);

  if (isnan(temperature)) {
    display.print("T: --");
  } else {
    display.printf("T:%.0f C", temperature);
  }

  display.setCursor(0, 42);

  if (isnan(humidity)) {
    display.print("H: --");
  } else {
    display.printf("H:%.0f %%", humidity);
  }
}

void drawSwitchPage() {
  drawHeader("SWITCH");

  display.setTextSize(2);
  display.setCursor(0, 18);
  display.printf("Front:%s", btnFront.stable ? "ON" : "off");

  display.setCursor(0, 42);
  display.printf("Back :%s", btnBack.stable ? "ON" : "off");
}

void drawI2cPage() {
  drawHeader("I2C BUS");

  display.setTextSize(1);
  display.setCursor(0, 14);
  display.printf("SDA:%d SCL:%d", PIN_SDA, PIN_SCL);

  display.setCursor(0, 26);
  display.printf("Found: %d device(s)", foundCount);

  for (int i = 0; i < foundCount && i < 4; i++) {
    display.setCursor(0, 38 + i * 9);
    display.printf("0x%02X", foundAddrs[i]);
  }
}

void render() {
  if (!oledOk) return;

  display.clearDisplay();

  switch (currentPage) {
    case PAGE_DHT:
      drawDhtPage();
      break;

    case PAGE_SWITCH:
      drawSwitchPage();
      break;

    case PAGE_I2C:
      drawI2cPage();
      break;
  }

  display.display();
}

// ---------- Serial page information ----------
void printPageToSerial() {
  switch (currentPage) {
    case PAGE_DHT:
      Serial.printf("[DHT11] Temp: %.1f C  Humidity: %.1f %%\n",
                    temperature, humidity);
      break;

    case PAGE_SWITCH:
      Serial.printf("[SWITCH] Front: %s  Back: %s\n",
                    btnFront.stable ? "ON" : "off",
                    btnBack.stable ? "ON" : "off");
      break;

    case PAGE_I2C:
      Serial.printf("[I2C] %d device(s) found\n", foundCount);
      break;
  }
}

// ---------- Change page ----------
void changePage(int delta) {
  int oldPage = currentPage;

  currentPage = (currentPage + delta + PAGE_COUNT) % PAGE_COUNT;

  Serial.printf("[NAV] Page %d -> Page %d\n",
                oldPage + 1, currentPage + 1);

  if (currentPage == PAGE_I2C) {
    scanI2C();
  }

  printPageToSerial();
  render();
}

// ---------- Arduino setup ----------
void setup() {
  Serial.begin(115200);
  delay(500);

  Serial.println();
  Serial.println("===== ESP32 STARTING =====");

  btnFront.begin(PIN_FRONT);
  btnBack.begin(PIN_BACK);

  Serial.printf("[SETUP] Front button GPIO: %d\n", PIN_FRONT);
  Serial.printf("[SETUP] Back button GPIO: %d\n", PIN_BACK);

  Wire.begin(PIN_SDA, PIN_SCL);

  dht.begin();

  oledOk = display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR);

  if (!oledOk) {
    Serial.println("[ERROR] OLED not found at 0x3C");
  } else {
    Serial.println("[OK] OLED initialised");
  }

  scanI2C();

  Serial.println("[SETUP] Ready. Press either button to navigate.");

  render();
}

// ---------- Main loop ----------
void loop() {
  // Update button states
  btnFront.update();
  btnBack.update();

  // Debug raw back-button pin
  static int lastBackRaw = HIGH;
  int backRaw = digitalRead(PIN_BACK);

  if (backRaw != lastBackRaw) {
    Serial.printf("[DEBUG] Back GPIO %d: %s\n",
                  PIN_BACK,
                  backRaw == LOW ? "PRESSED" : "RELEASED");

    lastBackRaw = backRaw;
  }

  // Front button moves forward
  if (btnFront.wasPressed()) {
    Serial.println("[DEBUG] Front button event detected");
    changePage(+1);
  }

  // Back button moves backward
  if (btnBack.wasPressed()) {
    Serial.println("[DEBUG] Back button event detected");

    Serial.printf("[DEBUG] Page before: %d\n", currentPage + 1);

    changePage(-1);

    Serial.printf("[DEBUG] Page after: %d\n", currentPage + 1);
  }

  // Read DHT11 every two seconds
  if (millis() - lastDhtRead >= DHT_INTERVAL) {
    lastDhtRead = millis();

    float t = dht.readTemperature();
    float h = dht.readHumidity();

    if (!isnan(t) && !isnan(h)) {
      temperature = t;
      humidity = h;
    } else {
      Serial.println("[DEBUG] DHT11 read failed");
    }

    if (currentPage == PAGE_DHT) {
      printPageToSerial();
    }
  }

  // Refresh OLED every 100 ms
  static unsigned long lastRender = 0;

  if (millis() - lastRender >= 100) {
    lastRender = millis();
    render();
  }
}
