#!/usr/bin/env python3
import os
import subprocess
import sys

FUNCTION_MAP = {
    "build-ListProductsFunction": "list-products",
    "build-GetProductFunction": "get-product",
    "build-SearchProductsFunction": "search-products",
    "build-GetCartFunction": "get-cart",
    "build-AddToCartFunction": "add-to-cart",
    "build-ClearCartFunction": "clear-cart",
    "build-CreateOrderFunction": "create-order",
    "build-ListOrdersFunction": "list-orders",
    "build-GetOrderFunction": "get-order",
    "build-CreatePaymentIntentFunction": "create-payment-intent",
    "build-WebhookHandlerFunction": "webhook-handler",
    "build-RegisterUserFunction": "register-user",
    "build-LoginUserFunction": "login-user",
    "build-JWTAuthorizerFunction": "jwt-authorizer"
}

def build_function(func_name):
    func_dir = f"functions/{func_name}"
    print(f"Building {func_name}...")
    
    if not os.path.exists(func_dir):
        print(f"Directory not found: {func_dir}")
        return False
    
    cmd = [
        "go", "build",
        "-tags", "lambda.norpc",
        "-o", "bootstrap",
        "main.go"
    ]
    
    env = os.environ.copy()
    env["GOOS"] = "linux"
    env["GOARCH"] = "amd64"
    env["CGO_ENABLED"] = "0"
    
    result = subprocess.run(cmd, cwd=func_dir, env=env, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"Failed to build {func_name}")
        print(result.stderr)
        return False
    
    bootstrap_path = os.path.join(func_dir, "bootstrap")
    if os.path.exists(bootstrap_path):
        size = os.path.getsize(bootstrap_path)
        print(f"Built {func_name} ({size:,} bytes)")
        return True
    else:
        print(f"Bootstrap not created for {func_name}")
        return False

if __name__ == "__main__":
    if len(sys.argv) > 1:
        target = sys.argv[1]
        if target in FUNCTION_MAP:
            func = FUNCTION_MAP[target]
            success = build_function(func)
            sys.exit(0 if success else 1)
        else:
            print(f"Unknown target: {target}")
            sys.exit(1)
    else:
        print("Building all functions...\n")
        failed = []
        for target, func in FUNCTION_MAP.items():
            if not build_function(func):
                failed.append(func)
            print()
        
        if failed:
            print(f"\nFailed to build: {', '.join(failed)}")
            sys.exit(1)
        else:
            print("\nAll functions built successfully!")
            sys.exit(0)
