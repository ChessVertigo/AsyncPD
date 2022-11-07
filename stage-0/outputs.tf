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

output "commands" {
  value = {
    primary   = "gcloud alpha compute disks describe test-0-boot --project tf-playground-svpc-gce --zone europe-west3-c"
    secondary = "gcloud alpha compute disks describe test-0-boot --project tf-playground-svpc-gce-dr --zone europe-west4-c"
  }
}

output "disks" {
  value = {
    primary = {
      for k, v in google_compute_disk.primary : v.name => v.zone
    }
    secondary = {
      for k, v in google_compute_disk.secondary : v.name => v.zone
    }
  }
}

output "vms" {
  value = {
    for k, v in google_compute_instance.default :
    k => v.network_interface[0].network_ip
  }
}

