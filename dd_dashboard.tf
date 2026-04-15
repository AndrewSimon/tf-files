# Example Ordered Layout
resource "datadog_dashboard" "ordered_dashboard" {
  title       = "TLC Generic Dashboard Layout"
  description = "Created using the Datadog provider in Terraform"
  layout_type = "ordered"

  widget {
    alert_graph_definition {
      alert_id  = "18673345"
      viz_type  = "timeseries"
      title     = "CPU Utilization"
      live_span = "1h"
    }
    timeseries_definition {
      request {
        q    = "avg:system.cpu.user{*}"
      }
      title = "CPU Usage"
    }
  }

  widget {
    alert_graph_definition {
      alert_id  = "18673346"
      viz_type  = "timeseries"
      title     = "Disk Latency (over 500ms wait time)"
      live_span = "1h"
    }
    timeseries_definition {
      request {
        q    = "avg:system.disk.utilized{*} by {host}"
      }
      title = "Disk Latency"
    }
  }
  
  widget {
    hostmap_definition {
      request {
        fill {
          q = "avg:system.load.1{*} by {host}"
        }
      }
      node_type       = "host"
      group           = []
      no_group_hosts  = true
      no_metric_hosts = true
      scope           = ["region:${data.aws_region.current.region}", "aws_account:${data.aws_caller_identity.current.account_id}"]
      style {
        palette      = "yellow_to_green"
        palette_flip = true
        fill_min     = "10"
        fill_max     = "20"
      }
      title = "System Load (Green=Good, Yellow=Warning, Red=Bad)"
    }
  }

  widget {
    note_definition {
      content          = "Due to a lack of documentation on Terraform's Datadog provider dashboard resource, the best way to generate terraform hcl IaC for the dashboard is to manually add/update/delete widgets in TLC Generic Dashboard Layout, then run terraform plan to show the manual entries that will be replaced.  Update your hcl with key and value pairs of what will be replaced to match manual entries such that the plan offers no change and matches."
      background_color = "pink"
      font_size        = "14"
      text_align       = "left"
      show_tick        = true
      tick_edge        = "left"
      tick_pos         = "50%"
    }
  }

  widget {
    query_value_definition {
      request {
        q          = "avg:system.load.1{env:prod} by {account}"
        aggregator = "sum"
        conditional_formats {
          comparator = "<"
          value      = "2"
          palette    = "white_on_green"
        }
        conditional_formats {
          comparator = ">"
          value      = "2.2"
          palette    = "white_on_red"
        }
      }
      autoscale   = true
      custom_unit = "xx"
      precision   = "4"
      text_align  = "right"
      title       = "Widget Title"
      live_span   = "1h"
    }
  }

  widget {
    query_table_definition {
      request {
        q          = "avg:system.load.1{env:prod} by {account}"
        aggregator = "sum"
        limit      = "10"
        conditional_formats {
          comparator = "<"
          value      = "2"
          palette    = "white_on_green"
        }
        conditional_formats {
          comparator = ">"
          value      = "2.2"
          palette    = "white_on_red"
        }
      }
      title     = "Widget Title"
      live_span = "1h"
    }
  }

  widget {
    scatterplot_definition {
      request {
        x {
          q          = "avg:system.cpu.user{*} by {service, account}"
          aggregator = "max"
        }
        y {
          q          = "avg:system.mem.used{*} by {service, account}"
          aggregator = "min"
        }
      }
      color_by_groups = ["account", "apm-role-group"]
      xaxis {
        include_zero = true
        label        = "x"
        min          = "1"
        max          = "2000"
        scale        = "pow"
      }
      yaxis {
        include_zero = false
        label        = "y"
        min          = "5"
        max          = "2222"
        scale        = "log"
      }
      title     = "Widget Title"
      live_span = "1h"
    }
  }

  widget {
    servicemap_definition {
      service     = "master-db"
      filters     = ["env:prod", "datacenter:dc1"]
      title       = "env: prod, datacenter:dc1, service: master-db"
      title_size  = "16"
      title_align = "left"
    }
  }

  widget {
    timeseries_definition {
      request {
        q            = "avg:system.cpu.user{app:general} by {env}"
        display_type = "line"
        style {
          palette    = "warm"
          line_type  = "dashed"
          line_width = "thin"
        }
        metadata {
          expression = "avg:system.cpu.user{app:general} by {env}"
          alias_name = "Alpha"
        }
      }
      request {
        log_query {
          index = "mcnulty"
          compute_query {
            aggregation = "avg"
            facet       = "@duration"
            interval    = 5000
          }
          search_query = "status:info"
          group_by {
            facet = "host"
            limit = 10
            sort_query {
              aggregation = "avg"
              order       = "desc"
              facet       = "@duration"
            }
          }
        }
        display_type = "area"
      }
      request {
        apm_query {
          index = "apm-search"
          compute_query {
            aggregation = "avg"
            facet       = "@duration"
            interval    = 5000
          }
          search_query = "type:web"
          group_by {
            facet = "resource_name"
            limit = 50
            sort_query {
              aggregation = "avg"
              order       = "desc"
              facet       = "@string_query.interval"
            }
          }
        }
        display_type = "bars"
      }
      request {
        process_query {
          metric    = "process.stat.cpu.total_pct"
          search_by = "error"
          filter_by = ["active"]
          limit     = 50
        }
        display_type = "area"
      }
      marker {
        display_type = "error dashed"
        label        = " z=6 "
        value        = "y = 4"
      }
      marker {
        display_type = "ok solid"
        value        = "10 < y < 999"
        label        = " x=8 "
      }
      title       = "Widget Title"
      show_legend = true
      legend_size = "2"
      live_span   = "1h"
      event {
        q = "sources:test tags:1"
      }
      event {
        q = "sources:test tags:2"
      }
      yaxis {
        scale        = "log"
        include_zero = false
        max          = 100
      }
    }
  }

  widget {
    toplist_definition {
      request {
        q = "avg:system.cpu.user{app:general} by {env}"
        conditional_formats {
          comparator = "<"
          value      = "2"
          palette    = "white_on_green"
        }
        conditional_formats {
          comparator = ">"
          value      = "2.2"
          palette    = "white_on_red"
        }
      }
      title = "Widget Title"
    }
  }

  widget {
    group_definition {
      layout_type = "ordered"
      title       = "Group Widget"

      widget {
        note_definition {
          content          = "cluster note widget"
          background_color = "pink"
          font_size        = "14"
          text_align       = "center"
          show_tick        = true
          tick_edge        = "left"
          tick_pos         = "50%"
        }
      }

      widget {
        alert_graph_definition {
          alert_id  = "123"
          viz_type  = "toplist"
          title     = "Alert Graph"
          live_span = "1h"
        }
      }
    }
  }

  widget {
    service_level_objective_definition {
      title             = "Widget Title"
      view_type         = "detail"
      slo_id            = "56789"
      show_error_budget = true
      view_mode         = "overall"
      time_windows      = ["7d", "previous_week"]
    }
  }

  template_variable {
    name    = "var_1"
    prefix  = "host"
    defaults = ["aws"]
  }
  template_variable {
    name    = "var_2"
    prefix  = "service_name"
    defaults = ["autoscaling"]
  }

  template_variable_preset {
    name = "preset_1"
    template_variable {
      name  = "var_1"
      values = ["host.dc"]
    }
    template_variable {
      name  = "var_2"
      values = ["my_service"]
    }
  }
}
