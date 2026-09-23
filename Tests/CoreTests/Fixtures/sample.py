"""Fixture for the Python lexer."""
import os


def main(value: int = 42) -> str:
    # comment
    if value > 10:
        return f"big: {value}"
    return 'small'


if __name__ == "__main__":
    print(main())
