/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  additional_disks = merge(flatten([
    for k, v in local.vms : [
      for kd, vd in try(v.additional_disks, {}) : {
        "${k}-${kd}" = merge(vd, { vm = k })
      }
    ]
  ])...)
  boot_disks = {
    for k, v in local.vms : "${k}-boot" => merge(v.boot_disk, { vm = k })
  }
  disks = merge(local.boot_disks, local.additional_disks)
  dr_disks = {
    for k, v in local.disks : k => v if try(local.vms[v.vm].dr, false)
  }
  replica_zones = merge(
    { for z in ["a", "b", "c"] : "europe-west3-${z}" => "europe-west4-${z}" }
  )
  vms = {
    for f in fileset("../data/prod", "*.json") :
    trimsuffix(basename(f), ".json") => yamldecode(file("../data/prod/${f}"))
  }
}

resource "google_compute_disk" "primary" {
  provider = google-asyncpd
  for_each = local.disks
  project  = local.vms[each.value.vm].project
  name     = each.key
  type     = each.value.type
  zone     = local.vms[each.value.vm].zone
  image    = try(each.value.image, null)
  size     = each.value.size
}

resource "google_compute_disk" "secondary" {
  provider = google-asyncpd
  for_each = local.dr_disks
  project = (
    var.x-project
    ? "${local.vms[each.value.vm].project}-dr"
    : local.vms[each.value.vm].project
  )
  name  = each.key
  type  = each.value.type
  zone  = local.replica_zones[local.vms[each.value.vm].zone]
  image = null
  size  = each.value.size
  async_primary_disk {
    disk = google_compute_disk.primary[each.key].id
  }
}

resource "google_compute_disk_async_replication" "replication" {
  provider     = google-asyncpd
  for_each     = local.dr_disks
  primary_disk = google_compute_disk.primary[each.key].id
  secondary_disk {
    disk = google_compute_disk.secondary[each.key].id
  }
}

resource "google_compute_instance" "default" {
  provider     = google-asyncpd
  for_each     = local.vms
  project      = each.value.project
  name         = each.key
  zone         = each.value.zone
  machine_type = each.value.type
  boot_disk {
    auto_delete = false
    source      = google_compute_disk.primary["${each.key}-boot"].id
  }
  dynamic "attached_disk" {
    for_each = try(each.value.additional_disks, {})
    iterator = disk
    content {
      device_name = disk.key
      source      = google_compute_disk.primary["${each.key}-${disk.key}"].id
    }
  }
  dynamic "network_interface" {
    for_each = toset(each.value.subnets)
    iterator = subnet
    content {
      subnetwork = subnet.key
    }
  }
  metadata = {
    user-data = templatefile("cloud-config.yaml", {
      disks = {
        for k, v in try(each.value.additional_disks, {}) :
        k => replace(k, "-", "\\x2d")
      }
    })
  }
  tags = ["ssh"]
}
