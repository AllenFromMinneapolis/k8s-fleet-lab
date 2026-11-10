"""Orders API: a tiny store app instrumented with OpenTelemetry.

It is started with `opentelemetry-instrument python app.py`. That wrapper is the
"auto-instrumentation": with no code at all it traces every HTTP request and records
request-count/latency metrics, then ships them to the Collector (OTEL_* env vars).

The code below adds the "manual" part: our own spans (steps inside a request)
and our own business metrics (orders placed, order value).
"""
import random
import time

from flask import Flask, jsonify
from opentelemetry import metrics, trace
from opentelemetry.trace import Status, StatusCode

app = Flask(__name__)

tracer = trace.get_tracer("orders-app")
meter = metrics.get_meter("orders-app")

orders_placed = meter.create_counter(
    "orders_placed", unit="{order}", description="Orders successfully placed")
order_value = meter.create_histogram(
    "order_value", unit="{USD}", description="Dollar value of each order")

MENU = {"coffee": 3.50, "sandwich": 8.25, "salad": 9.75, "cookie": 2.00}


@app.get("/menu")
def menu():
    return jsonify(MENU)


@app.get("/order")
def order():
    item = random.choice(list(MENU))
    quantity = random.randint(1, 3)

    # The span for this HTTP request was started by auto-instrumentation; add details to it.
    request_span = trace.get_current_span()
    request_span.set_attribute("order.item", item)
    request_span.set_attribute("order.quantity", quantity)

    # Step 1: inventory lookup. About 1 in 10 misses the cache and is slow.
    with tracer.start_as_current_span("check_inventory") as span:
        cache_hit = random.random() > 0.1
        span.set_attribute("inventory.cache_hit", cache_hit)
        time.sleep(random.uniform(0.005, 0.03) if cache_hit else random.uniform(0.3, 0.6))

    # Step 2: take payment. About 1 in 20 fails.
    with tracer.start_as_current_span("charge_card") as span:
        time.sleep(random.uniform(0.02, 0.15))
        if random.random() < 0.05:
            error = RuntimeError("payment gateway timeout")
            span.record_exception(error)
            span.set_status(Status(StatusCode.ERROR, str(error)))
            return jsonify(error=str(error)), 500

    total = round(MENU[item] * quantity, 2)
    orders_placed.add(1, {"item": item})
    order_value.record(total, {"item": item})
    return jsonify(item=item, quantity=quantity, total=total)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
