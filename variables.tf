variable "image_id" {
  type = string
  description = "image id"
}

variable "instance_type"{
  type = string
  default = "t4g.nano"
  description = "instance type"
}

variable "multi_az"{
  type = bool
  default = false
  description = "set to true to deploy in all provided availability zones"
}

variable "name_prefix"{
  type = string
  description = "prefix for the aws resources"
}

variable "private_subnet_ids" {
  type = list(string) 
  description = "private subnets" 
}

variable "public_subnet_ids"{
  type = list(string) 
  description = "public subnets"
}

variable "vpc_id" {
  type = string
  description = "vpc id"
}



