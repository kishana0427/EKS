resource "aws_vpc" "eks_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "eks-vpc"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "eks_subnet_public" {
  count			  = length(data.aws_availability_zones.available.names)
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block,8,count.index+1)
  availability_zone       = element(data.aws_availability_zones.available.names,count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-subnet-public-${(count.index+1)}"
  }
} 

resource "aws_subnet" "eks_subnet_private" {
  count                   = length(data.aws_availability_zones.available.names)
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block,8,count.index+4)
  availability_zone       = element(data.aws_availability_zones.available.names,count.index)
  map_public_ip_on_launch = false

  tags = {
    Name = "eks-subnet-private-${(count.index+1)}"
  }
}



==============================================================================================
subnets with count

You can create multiple subnets dynamically in Terraform using the count meta-argument. 
The count argument allows you to specify how many instances of a resource you want to create, 
and you can use it to create subnets across multiple availability zones based on a list or data source.
Example: Create Subnets Using count

If you want to create a set of subnets in multiple availability zones (AZs) dynamically, you can use 
the count argument with the aws_availability_zones data source and cidrsubnet function. 
This example creates a subnet in each available AZ in your VPC.

Here’s how you can do it:
Terraform Code to Create Subnets Dynamically Using count

# Fetch the availability zones in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Create a VPC
resource "aws_vpc" "eks_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "eks-vpc"
  }
}

# Create subnets across the available AZs
resource "aws_subnet" "eks_subnet" {
  count = length(data.aws_availability_zones.available.names)  # Creates a subnet for each AZ

  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-subnet-${element(data.aws_availability_zones.available.names, count.index)}"
  }
}

Explanation:

    data "aws_availability_zones" "available": This data source fetches the available availability zones for the current AWS region.

    count = length(data.aws_availability_zones.available.names): This counts the number of availability zones available. Each zone will get a separate subnet.

    cidrsubnet(aws_vpc.eks_vpc.cidr_block, 8, count.index): The cidrsubnet function calculates a subnet's CIDR block based on the VPC's CIDR block and an index. It divides the CIDR block into smaller subnets. The 8 is the new subnet size (you can adjust it as needed).

    element(data.aws_availability_zones.available.names, count.index): This function fetches the AZ name for each subnet. The count.index ensures that each subnet is created in a different AZ.

    map_public_ip_on_launch = true: This is an optional setting for public subnets that automatically assigns public IPs to instances launched in these subnets. You can set it to false if you want private subnets.

    tags: This defines tags for your subnets, including one that names the subnet based on the availability zone.

Output Example:

After running terraform apply, Terraform will create a subnet for each availability zone in your region. The number of subnets created will match the number of AZs available in your region.

terraform apply

For example, if the available AZs are us-west-2a, us-west-2b, and us-west-2c, you’ll get three subnets with names like eks-subnet-us-west-2a, eks-subnet-us-west-2b, and eks-subnet-us-west-2c.
Conclusion

This approach allows you to create a dynamic number of subnets that are evenly distributed across available availability zones without having to hard-code anything. By using count and the cidrsubnet function, you can create subnets that scale easily with the number of availability zones in the region.
You said:
I want to start subnet from 10.0.1.0/24  instead 10.0.0.0/24 how
ChatGPT said:

If you want to start your subnets from 10.0.1.0/24 instead of 10.0.0.0/24, you need to adjust the cidrsubnet function slightly.
Understanding CIDR Subnet Calculation:

The cidrsubnet function is used to break down a larger CIDR block into smaller subnets. By default, your aws_vpc has a 10.0.0.0/16 CIDR block, which means that you have the entire 10.0.0.0/16 range available (i.e., 10.0.0.0 to 10.0.255.255). When you're creating subnets from this range, you'd typically specify the network size (e.g., /24).

However, to ensure the first subnet starts from 10.0.1.0/24, you need to use the cidrsubnet function in such a way that the first subnet starts from the 10.0.1.0 range.
Solution: Adjust the Start Point

We can adjust the cidrsubnet function by adding an offset to start the subnet allocation from 10.0.1.0/24 instead of 10.0.0.0/24.
Updated Terraform Code:

# Fetch the availability zones in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Create a VPC
resource "aws_vpc" "eks_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "eks-vpc"
  }
}

# Create subnets across the available AZs
resource "aws_subnet" "eks_subnet" {
  count = length(data.aws_availability_zones.available.names)  # Creates a subnet for each AZ

  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = cidrsubnet("10.0.0.0/16", 8, count.index + 1)  # Start from 10.0.1.0/24
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-subnet-${element(data.aws_availability_zones.available.names, count.index)}"
  }
}

Key Changes:

    cidrsubnet("10.0.0.0/16", 8, count.index + 1):

        The cidrsubnet function is used to break the 10.0.0.0/16 range into smaller subnets. The second argument 8 specifies that each subnet will have a /24 mask (because 16 + 8 = 24).

        By adding count.index + 1, we effectively start the subnets from 10.0.1.0/24 instead of 10.0.0.0/24. The count.index starts at 0, so adding 1 will make the first subnet start from 10.0.1.0/24, then 10.0.2.0/24, and so on.

CIDR Subnet Explanation:

    cidrsubnet("10.0.0.0/16", 8, count.index + 1):

        "10.0.0.0/16": The base CIDR block for the VPC.

        8: The subnet size (/24).

        count.index + 1: The index adjustment that shifts the starting point by 1, starting at 10.0.1.0/24.

What Happens:

    The first subnet will be created in 10.0.1.0/24, the second in 10.0.2.0/24, and so on, depending on the number of availability zones available in the region.

Example Output for 3 AZs:

Assuming you have 3 availability zones available (us-west-2a, us-west-2b, us-west-2c), the resulting subnets would be:

    eks-subnet-us-west-2a with 10.0.1.0/24

    eks-subnet-us-west-2b with 10.0.2.0/24

    eks-subnet-us-west-2c with 10.0.3.0/24

Conclusion:

By adjusting the cidrsubnet calculation with the +1 offset, you can start creating subnets from 10.0.1.0/24 instead of 10.0.0.0/24. This approach ensures that your subnets start from a higher IP block while still making use of the 10.0.0.0/16 range.
