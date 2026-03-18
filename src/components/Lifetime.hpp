#pragma once

// Counts down to zero; the owning system destroys the entity when it hits 0.
struct Lifetime {
    float remaining = 0.f;   // seconds

    Lifetime() = default;
    explicit Lifetime(float seconds) : remaining(seconds) {}
};
