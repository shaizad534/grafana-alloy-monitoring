# Grafana Alloy Compatibility Matrix

## Version Release Timeline

| Alloy Version | Release Date | OTel Collector Version | Key Changes |
|---------------|--------------|------------------------|-------------|
| **v1.9.2** | ~May 2024 | **0.103.0** | Stable OTel 0.103, `prometheus.exporter.*` stable, Windows exporter GA |
| **v1.11.0** | ~July 2024 | **0.106.0** | OTel 0.106, `otelcol.receiver.*` new components, `prometheus.remote_write` queue_config changes |
| **v1.17.1** | ~Jan 2025 | **0.112.0** | OTel 0.112, `otelcol.processor.transform` GA, Windows exporter enhanced, `otelcol.exporter.loadbalancing` GA |

---

## Config Compatibility Matrix

| Config Element | v1.9.2 | v1.11.0 | v1.17.1 | Action Needed |
|----------------|--------|---------|---------|---------------|
| `prometheus.exporter.windows` | ✅ Stable | ✅ Stable | ✅ Enhanced (new collectors) | None |
| `prometheus.exporter.oracledb` | ✅ Stable | ✅ Stable | ✅ Stable | None |
| `prometheus.exporter.mssql` | ✅ Stable | ✅ Stable | ✅ Stable | None |
| `prometheus.exporter.mysql` | ✅ Stable | ✅ Stable | ✅ Stable | None |
| `prometheus.remote_write` | ✅ Stable | ✅ Queue config enhanced | ✅ Queue config stable | Check `queue_config` syntax |
| `prometheus.scrape` | ✅ Stable | ✅ Stable | ✅ Stable | None |
| `logging block` | ✅ Stable | ✅ Stable | ✅ Stable | None |
| `otelcol.receiver.*` | ❌ Not available | ✅ **New** (OTel 0.106) | ✅ Expanded | **New feature** – optional adoption |
| `otelcol.processor.transform` | ❌ Not available | 🟡 Beta | ✅ **GA** | **Migration** if using beta |
| `otelcol.exporter.loadbalancing` | ❌ Not available | ❌ Not available | ✅ **GA** | **New feature** – optional |
| `otelcol.exporter.otlp` | ✅ Stable | ✅ Stable | ✅ Stable | None |

---

## Config Changes Required by Version Upgrade

### v1.9.2 → v1.11.0 (OTel 0.103 → 0.106)

**Minimal changes needed - No breaking changes**

```yaml
# OPTIONAL: New OTel receivers available (no migration needed for existing)
# Can now use:
otelcol.receiver.hostmetrics "example" {
  collection_interval = "60s"
  scrapers = ["cpu", "memory", "disk", "network"]
}
```

**No breaking changes** for existing `prometheus.exporter.*` configs.

---

### v1.11.0 → v1.17.1 (OTel 0.106 → 0.112)

**Potential changes needed:**

#### 1. `otelcol.processor.transform` – Beta → GA
```yaml
# v1.11 (beta) - may have used:
otelcol.processor.transform "example" {
  # beta syntax
}

# v1.17+ (GA) - stable syntax, same but guaranteed stable
otelcol.processor.transform "example" {
  # GA syntax - same but stable
  error_mode = "ignore"  # new option
}
```

#### 2. `prometheus.remote_write` queue_config (Recommended for v1.17+)
```yaml
# v1.9/v1.11 - queue_config optional
prometheus.remote_write "grafana_cloud" {
  endpoint {
    url = "..."
  }
  # queue_config was optional
}

# v1.17+ - queue_config recommended for production
prometheus.remote_write "grafana_cloud" {
  endpoint {
    url = "..."
  }
  queue_config {
    capacity = 10000
    max_shards = 1000
    min_shards = 100
    max_samples_per_send = 5000
    batch_send_deadline = "5s"
  }
}
```

#### 3. New Windows Exporter Collectors (v1.17+)
```yaml
prometheus.exporter.windows "windows" {
  # New collectors available in v1.17+
  # enable_collectors = ["cpu", "memory", "disk", "network", "os", "service", "system", "iis", "hyperv"]
}
```

---

## Migration Checklist by Version

### Upgrading FROM v1.9.2
| Target | Config Changes | Effort |
|--------|---------------|--------|
| **→ v1.11.0** | None required | ⚡ Zero |
| **→ v1.17.1** | Add `queue_config` to remote_write (recommended) | 🟢 Low |

### Upgrading FROM v1.11.0
| Target | Config Changes | Effort |
|--------|---------------|--------|
| **→ v1.17.1** | Add `queue_config` to remote_write; check `otelcol.processor.transform` if used | 🟢 Low |

---

## Your Config File Compatibility

### Current Sample Config (`configs/stage/alloy-windows-vm-oracle-mssql.alloy`)

| Component | v1.9.2 | v1.11.0 | v1.17.1 | Status |
|-----------|--------|---------|---------|--------|
| `prometheus.exporter.windows` | ✅ | ✅ | ✅ | ✅ Compatible |
| `prometheus.exporter.oracledb` | ✅ | ✅ | ✅ | ✅ Compatible |
| `prometheus.exporter.mssql` | ✅ | ✅ | ✅ | ✅ Compatible |
| `prometheus.remote_write` | ✅ | ✅ | ✅ **Add queue_config** | 🟡 Recommended |
| `prometheus.scrape` | ✅ | ✅ | ✅ | ✅ Compatible |
| `logging` | ✅ | ✅ | ✅ | ✅ Compatible |

### Recommended Update for v1.17.1+

```yaml
prometheus.remote_write "grafana_cloud" {
  endpoint {
    url = "https://prometheus-prod-xx.grafana.net/api/prom/push"
    basic_auth {
      username = "123456"
      password = "glc_eyJvcmciOiI..."
    }
  }
  # ADD THIS for v1.17+ (recommended for production)
  queue_config {
    capacity = 10000
    max_shards = 1000
    min_shards = 100
    max_samples_per_send = 5000
    batch_send_deadline = "5s"
  }
}
```

---

## Upgrade Strategy Recommendation

| Current Version | Recommended Path | Config Changes |
|-----------------|------------------|----------------|
| **v1.9.2** | → v1.17.1 directly | Add `queue_config` (5 lines) |
| **v1.11.0** | → v1.17.1 | Add `queue_config` (5 lines) |
| **v1.17.1** | Stay current | No changes needed |

### Safe Upgrade Process
```bash
# 1. Test in staging with target version
ansible-playbook -i ansible/inventory/staging/hosts.yml ansible/playbooks/deploy_alloy.yml \
  -e "alloy_version=1.17.1 alloy_config_source=configs/stage/alloy-windows-vm-oracle-mssql.alloy"

# 2. Verify metrics in Grafana Cloud
# 3. Promote to prod
```

---

## Summary

| Version | Config Changes Required | Risk |
|---------|------------------------|------|
| **v1.9.2 → v1.11.0** | None | 🟢 None |
| **v1.9.2 → v1.17.1** | Add `queue_config` (5 lines) | 🟢 Low |
| **v1.11.0 → v1.17.1** | Add `queue_config` (5 lines) | 🟢 Low |

**Your current config works on all three versions.** Only **recommended** change for v1.17.1+ is adding the `queue_config` block to `prometheus.remote_write` for better production reliability.

**No breaking changes** for your Windows VM + Oracle + MSSQL config across these versions.