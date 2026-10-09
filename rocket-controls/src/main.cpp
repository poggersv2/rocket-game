#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <DHT.h>

// ---------- Pins ----------
#define PIN_SDA     21
#define PIN_SCL     22
#define PIN_FRONT   4
#define PIN_BACK    27
#define PIN_DHT     19
#define PIN_POT     34   // ADC1, analog only
#define PIN_ENC_CLK 32   // encoder A
#define PIN_ENC_DT  33   // encoder B
#define PIN_ENC_SW  18   // encoder push button
#define PIN_BUZZER  25

// ---------- Buzzer ----------
// 1 = passive buzzer (we generate the tone, pitch can change)
// 0 = active buzzer (fixed built-in tone, on/off only)
#define BUZZER_PASSIVE 1

unsigned long buzzerOffAt = 0;

void beep(unsigned int freq, unsigned int ms) {
#if BUZZER_PASSIVE
  tone(PIN_BUZZER, freq, ms);
#else
  digitalWrite(PIN_BUZZER, HIGH);
  buzzerOffAt = millis() + ms;
#endif
}

// ---------- Encoder behaviour ----------
#define ENC_STEPS_PER_DETENT 4   // 4 for most encoders (KY-040); use 2 or 1 if it skips
#define ENC_DIR              1   // set to -1 to reverse direction
#define ENC_MIN              0   // lowest value (clamped)
#define ENC_MAX              100 // highest value (clamped)
#define ENC_RESET_VALUE      0   // value set when the knob is pressed

volatile int32_t encRaw = 0;
volatile uint8_t encState = 0;

// Quadrature state table: index = (previous AB << 2) | current AB
static const int8_t ENC_TABLE[16] = {
   0, -1,  1,  0,
   1,  0,  0, -1,
  -1,  0,  0,  1,
   0,  1, -1,  0
};

void IRAM_ATTR encISR() {
  encState = ((encState << 2) |
              (digitalRead(PIN_ENC_CLK) << 1) |
               digitalRead(PIN_ENC_DT)) & 0x0F;
  encRaw += ENC_DIR * ENC_TABLE[encState];
}

// Encoder push button (debounced, active-low)
bool encBtnStable = false;
bool encBtnLast = false;
unsigned long encBtnChange = 0;

// ---------- Display ----------
Adafruit_SSD1306 display(128, 64, &Wire, -1);
bool oledOk = false;

// ---------- DHT11 ----------
DHT dht(PIN_DHT, DHT11);
float temperature = NAN;
float humidity = NAN;
unsigned long lastDhtRead = 0;

void setup() {
  Serial.begin(115200);

  pinMode(PIN_FRONT, INPUT_PULLUP);
  pinMode(PIN_BACK, INPUT_PULLUP);

  pinMode(PIN_ENC_CLK, INPUT_PULLUP);
  pinMode(PIN_ENC_DT, INPUT_PULLUP);
  pinMode(PIN_ENC_SW, INPUT_PULLUP);

  pinMode(PIN_BUZZER, OUTPUT);
  digitalWrite(PIN_BUZZER, LOW);

  // Seed the decoder with the current pin state, then listen for changes
  encState = (digitalRead(PIN_ENC_CLK) << 1) | digitalRead(PIN_ENC_DT);
  attachInterrupt(digitalPinToInterrupt(PIN_ENC_CLK), encISR, CHANGE);
  attachInterrupt(digitalPinToInterrupt(PIN_ENC_DT), encISR, CHANGE);

  Wire.begin(PIN_SDA, PIN_SCL);
  dht.begin();

  oledOk = display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  if (!oledOk) Serial.println("OLED not found at 0x3C");

  beep(2000, 80);  // startup chirp
}

void loop() {
  // Read DHT11 every 2 seconds, keep last good values
  if (millis() - lastDhtRead >= 2000) {
    lastDhtRead = millis();
    float t = dht.readTemperature();
    float h = dht.readHumidity();
    if (!isnan(t) && !isnan(h)) {
      temperature = t;
      humidity = h;
    }
  }

  // Switch (pressed/flipped = 1)
  int front = digitalRead(PIN_FRONT) == LOW;
  int back  = digitalRead(PIN_BACK) == LOW;

  int pot = analogRead(PIN_POT);

  // Encoder push button: debounce, press resets the value
  bool r = (digitalRead(PIN_ENC_SW) == LOW);
  if (r != encBtnLast) {
    encBtnLast = r;
    encBtnChange = millis();
  }
  if (millis() - encBtnChange >= 30 && r != encBtnStable) {
    encBtnStable = r;
    if (encBtnStable) {
      noInterrupts();
      encRaw = ENC_RESET_VALUE * ENC_STEPS_PER_DETENT;
      interrupts();
      beep(1000, 120);  // knob pressed
    }
  }

  // Encoder value: clamp, then convert steps to detents
  noInterrupts();
  if (encRaw > ENC_MAX * ENC_STEPS_PER_DETENT) encRaw = ENC_MAX * ENC_STEPS_PER_DETENT;
  if (encRaw < ENC_MIN * ENC_STEPS_PER_DETENT) encRaw = ENC_MIN * ENC_STEPS_PER_DETENT;
  int32_t raw = encRaw;
  interrupts();
  int enc = raw / ENC_STEPS_PER_DETENT;

  // Beeps on changes
  static int lastEnc = 0, lastFront = 0, lastBack = 0;
  if (enc != lastEnc) {
    lastEnc = enc;
    beep(map(enc, ENC_MIN, ENC_MAX, 500, 2500), 15);  // pitch follows the value
  }
  if (front != lastFront || back != lastBack) {
    lastFront = front;
    lastBack = back;
    beep(front ? 1500 : 800, 60);  // switch flipped
  }

#if !BUZZER_PASSIVE
  if (buzzerOffAt && millis() >= buzzerOffAt) {
    digitalWrite(PIN_BUZZER, LOW);
    buzzerOffAt = 0;
  }
#endif

  // Serial
  static unsigned long lastPrint = 0;
  if (millis() - lastPrint >= 1000) {
    lastPrint = millis();
    Serial.printf("%.1f %.1f %d %d %d %d %d\n",
                  temperature, humidity, front, back, pot, enc, encBtnStable);
  }

  // OLED: raw values only, refreshed every 100 ms
  static unsigned long lastDraw = 0;
  if (oledOk && millis() - lastDraw >= 100) {
    lastDraw = millis();
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);

    display.setCursor(0, 0);
    display.printf("Temp: %.0f", temperature);
    display.setCursor(0, 10);
    display.printf("Hum: %.0f", humidity);
    display.setCursor(0, 20);
    display.printf("F:%d B:%d", front, back);
    display.setCursor(0, 30);
    display.printf("Pot: %d", pot);
    display.setCursor(0, 40);
    display.printf("Enc: %d Sw:%d", enc, encBtnStable);

    display.display();
  }

  delay(1);
}