import random

TENANTS = ["acme", "globex", "initech", "umbrella", "soylent"]

SCENARIOS = ("normal", "slow_retrieval", "token_spike", "tenant_error")

MODELS = {"small": 0.00025, "large": 0.0021}


def pick_scenario(weights):
    return random.choices(SCENARIOS, weights=weights, k=1)[0]


def retrieval_latency_ms(scenario):
    if scenario == "slow_retrieval":
        return random.uniform(4200, 9500)
    return random.lognormvariate(4.5, 0.45)


def llm_latency_ms(scenario, tokens_out):
    base = 380 + tokens_out * random.uniform(7.5, 12.0)
    if scenario == "token_spike":
        base *= random.uniform(1.1, 1.4)
    return base * random.uniform(0.85, 1.2)


def token_counts(scenario, docs_found):
    tokens_in = 180 + docs_found * random.randint(220, 480)
    if scenario == "token_spike":
        tokens_out = random.randint(1400, 2600)
    else:
        tokens_out = random.randint(60, 320)
    return tokens_in, tokens_out


def docs_found(scenario):
    if scenario == "slow_retrieval":
        return random.randint(9, 18)
    return random.randint(1, 6)


def cost_usd(model, tokens_in, tokens_out):
    rate = MODELS[model]
    return round((tokens_in * 0.4 + tokens_out) * rate / 1000, 6)
