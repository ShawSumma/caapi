module bindings.vk;

// Minimal Vulkan declarations for D.
// We link -lvulkan so these are resolved at link time.

alias VkFlags = uint;
alias VkBool32 = uint;
alias VkDeviceSize = ulong;
alias VkSampleCountFlagBits = uint;

// Handles (non-dispatchable are uint64, dispatchable are pointers)
alias VkInstance = void*;
alias VkPhysicalDevice = void*;
alias VkDevice = void*;
alias VkQueue = void*;
alias VkCommandBuffer = void*;
alias VkSurfaceKHR = ulong;
alias VkSwapchainKHR = ulong;
alias VkImage = ulong;
alias VkImageView = ulong;
alias VkRenderPass = ulong;
alias VkFramebuffer = ulong;
alias VkCommandPool = ulong;
alias VkSemaphore = ulong;
alias VkFence = ulong;
alias VkPipeline = ulong;
alias VkPipelineLayout = ulong;
alias VkShaderModule = ulong;

enum VkResult : int {
    VK_SUCCESS = 0,
    VK_NOT_READY = 1,
    VK_TIMEOUT = 2,
    VK_SUBOPTIMAL_KHR = 1000001003,
    VK_ERROR_OUT_OF_DATE_KHR = -1000001004,
}

enum VkStructureType : int {
    VK_STRUCTURE_TYPE_APPLICATION_INFO = 0,
    VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1,
    VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO = 2,
    VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO = 3,
    VK_STRUCTURE_TYPE_SUBMIT_INFO = 4,
    VK_STRUCTURE_TYPE_FENCE_CREATE_INFO = 8,
    VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO = 9,
    VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO = 15,
    VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO = 37,
    VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO = 38,
    VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO = 39,
    VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO = 40,
    VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO = 42,
    VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO = 43,
    VK_STRUCTURE_TYPE_PRESENT_INFO_KHR = 1000001001,
    VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR = 1000001000,
    VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO = 12,
    VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO = 5,
    VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO = 16,
    VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO = 18,
    VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO = 19,
    VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO = 20,
    VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO = 22,
    VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO = 23,
    VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO = 24,
    VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO = 25,
    VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO = 26,
    VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO = 27,
    VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO = 28,
    VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO = 30,
    VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO = 14,
    VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO = 32,
    VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO = 33,
    VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO = 34,
    VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET = 35,
    VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO = 29,
    VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO = 31,
    VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER = 44,
    VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER = 45,
}

enum VkDescriptorType : int {
    VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER = 1,
    VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER = 6,
    VK_DESCRIPTOR_TYPE_STORAGE_BUFFER = 7,
    VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC = 8,
    VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT = 10,
}

enum VkVertexInputRateExt : int {
    VK_VERTEX_INPUT_RATE_INSTANCE = 1,
}

enum VkFormat : int {
    VK_FORMAT_UNDEFINED = 0,
    VK_FORMAT_R8G8B8A8_UNORM = 37,
    VK_FORMAT_R8G8B8A8_SRGB = 43,
    VK_FORMAT_B8G8R8A8_UNORM = 44,
    VK_FORMAT_B8G8R8A8_SRGB = 50,
    VK_FORMAT_D32_SFLOAT = 126,
}

enum VkColorSpaceKHR : int {
    VK_COLOR_SPACE_SRGB_NONLINEAR_KHR = 0,
}

enum VkPresentModeKHR : int {
    VK_PRESENT_MODE_IMMEDIATE_KHR = 0,
    VK_PRESENT_MODE_MAILBOX_KHR = 1,
    VK_PRESENT_MODE_FIFO_KHR = 2,
}

enum VkImageLayout : int {
    VK_IMAGE_LAYOUT_UNDEFINED = 0,
    VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL = 2,
    VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL = 3,
    VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL = 4,
    VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL = 5,
    VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL = 7,
    VK_IMAGE_LAYOUT_PRESENT_SRC_KHR = 1000001002,
}

enum VkImageType : int {
    VK_IMAGE_TYPE_2D = 1,
}

enum VkImageTiling : int {
    VK_IMAGE_TILING_OPTIMAL = 0,
}

enum VkCompareOp : int {
    VK_COMPARE_OP_LESS = 1,
    VK_COMPARE_OP_GREATER = 4,
}

enum VkAttachmentLoadOp : int {
    VK_ATTACHMENT_LOAD_OP_LOAD = 0,
    VK_ATTACHMENT_LOAD_OP_CLEAR = 1,
}

enum VkAttachmentStoreOp : int {
    VK_ATTACHMENT_STORE_OP_STORE = 0,
    VK_ATTACHMENT_STORE_OP_DONT_CARE = 1,
}

enum VkPipelineBindPoint : int {
    VK_PIPELINE_BIND_POINT_GRAPHICS = 0,
}

enum VkCommandBufferLevel : int {
    VK_COMMAND_BUFFER_LEVEL_PRIMARY = 0,
}

enum VkSubpassContents : int {
    VK_SUBPASS_CONTENTS_INLINE = 0,
}

enum VkImageViewType : int {
    VK_IMAGE_VIEW_TYPE_2D = 1,
    VK_IMAGE_VIEW_TYPE_2D_ARRAY = 5,
}

enum VkComponentSwizzle : int {
    VK_COMPONENT_SWIZZLE_IDENTITY = 0,
}

enum VkImageAspectFlagBits : uint {
    VK_IMAGE_ASPECT_COLOR_BIT = 0x00000001,
    VK_IMAGE_ASPECT_DEPTH_BIT = 0x00000002,
}

enum VkSharingMode : int {
    VK_SHARING_MODE_EXCLUSIVE = 0,
}

enum VkImageUsageFlagBits : uint {
    VK_IMAGE_USAGE_TRANSFER_DST_BIT = 0x00000002,
    VK_IMAGE_USAGE_SAMPLED_BIT = 0x00000004,
    VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT = 0x00000010,
    VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT = 0x00000020,
    VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT = 0x00000080,
}

enum VkCompositeAlphaFlagBitsKHR : uint {
    VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR = 0x00000001,
}

enum VkSurfaceTransformFlagBitsKHR : uint {
    VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR = 0x00000001,
}

enum VkCommandPoolCreateFlagBits : uint {
    VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT = 0x00000002,
}

enum VkFenceCreateFlagBits : uint {
    VK_FENCE_CREATE_SIGNALED_BIT = 0x00000001,
}

enum VkPipelineStageFlagBits : uint {
    VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT = 0x00000400,
}

enum VkShaderStageFlagBits : uint {
    VK_SHADER_STAGE_VERTEX_BIT = 0x00000001,
    VK_SHADER_STAGE_FRAGMENT_BIT = 0x00000010,
    VK_SHADER_STAGE_COMPUTE_BIT = 0x00000020,
}

enum VkAccessFlagBits : uint {
    VK_ACCESS_INDIRECT_COMMAND_READ_BIT = 0x00000001,
    VK_ACCESS_INPUT_ATTACHMENT_READ_BIT = 0x00000010,
    VK_ACCESS_SHADER_READ_BIT = 0x00000020,
    VK_ACCESS_SHADER_WRITE_BIT = 0x00000040,
    VK_ACCESS_COLOR_ATTACHMENT_READ_BIT = 0x00000080,
    VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT = 0x00000100,
    VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT = 0x00000200,
    VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT = 0x00000400,
}

enum VkPipelineStageFlagBitsExt : uint {
    VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT = 0x00000002,
    VK_PIPELINE_STAGE_VERTEX_SHADER_BIT = 0x00000008,
    VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT = 0x00000080,
    VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT = 0x00000100,
    VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT = 0x00000200,
    VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT = 0x00000800,
    VK_PIPELINE_STAGE_TRANSFER_BIT = 0x00001000,
}

enum VkVertexInputRate : int {
    VK_VERTEX_INPUT_RATE_VERTEX = 0,
}

enum VkPrimitiveTopology : int {
    VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST = 3,
}

enum VkPolygonMode : int {
    VK_POLYGON_MODE_FILL = 0,
}

enum VkCullModeFlagBits : uint {
    VK_CULL_MODE_NONE = 0,
    VK_CULL_MODE_BACK_BIT = 0x00000002,
}

enum VkFrontFace : int {
    VK_FRONT_FACE_COUNTER_CLOCKWISE = 0,
    VK_FRONT_FACE_CLOCKWISE = 1,
}

enum VkDynamicState : int {
    VK_DYNAMIC_STATE_VIEWPORT = 0,
    VK_DYNAMIC_STATE_SCISSOR = 1,
}

enum VkBufferUsageFlagBits : uint {
    VK_BUFFER_USAGE_TRANSFER_SRC_BIT = 0x00000001,
    VK_BUFFER_USAGE_VERTEX_BUFFER_BIT = 0x00000080,
    VK_BUFFER_USAGE_INDEX_BUFFER_BIT = 0x00000040,
    VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT = 0x00000010,
    VK_BUFFER_USAGE_STORAGE_BUFFER_BIT = 0x00000020,
    VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT = 0x00000100,
    VK_BUFFER_USAGE_TRANSFER_DST_BIT = 0x00000002,
}

alias VkSampler = ulong;
alias VkDescriptorSetLayout = ulong;
alias VkDescriptorPool = ulong;
alias VkDescriptorSet = ulong;

enum VK_WHOLE_SIZE = ulong.max;

enum VkMemoryPropertyFlagBits : uint {
    VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT = 0x00000001,
    VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT = 0x00000002,
    VK_MEMORY_PROPERTY_HOST_COHERENT_BIT = 0x00000004,
}

enum VkIndexType : int {
    VK_INDEX_TYPE_UINT32 = 1,
}

enum VkFormatExt : int {
    VK_FORMAT_R32G32B32_SFLOAT = 106,
}

enum VK_SUBPASS_EXTERNAL = ~0U;
enum VK_NULL_HANDLE = 0;
enum VK_QUEUE_GRAPHICS_BIT = 0x00000001;

struct VkExtent2D {
    uint width;
    uint height;
}

struct VkOffset2D {
    int x;
    int y;
}

struct VkRect2D {
    VkOffset2D offset;
    VkExtent2D extent;
}

struct VkClearColorValue {
    float[4] float32;
}

struct VkClearDepthStencilValue {
    float depth;
    uint stencil;
}

union VkClearValue {
    VkClearColorValue color;
    VkClearDepthStencilValue depthStencil;
}

struct VkImageCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    VkImageType imageType;
    VkFormat format;
    VkExtent3D extent;
    uint mipLevels;
    uint arrayLayers;
    uint samples;
    VkImageTiling tiling;
    uint usage;
    VkSharingMode sharingMode;
    uint queueFamilyIndexCount;
    const(uint)* pQueueFamilyIndices;
    VkImageLayout initialLayout;
}

struct VkPipelineDepthStencilStateCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    VkBool32 depthTestEnable;
    VkBool32 depthWriteEnable;
    VkCompareOp depthCompareOp;
    VkBool32 depthBoundsTestEnable;
    VkBool32 stencilTestEnable;
    // Stencil state fields - we don't use them; pad with zeros.
    uint front_failOp; uint front_passOp; uint front_depthFailOp; uint front_compareOp;
    uint front_compareMask; uint front_writeMask; uint front_reference;
    uint back_failOp; uint back_passOp; uint back_depthFailOp; uint back_compareOp;
    uint back_compareMask; uint back_writeMask; uint back_reference;
    float minDepthBounds;
    float maxDepthBounds;
}

struct VkComponentMapping {
    VkComponentSwizzle r;
    VkComponentSwizzle g;
    VkComponentSwizzle b;
    VkComponentSwizzle a;
}

struct VkImageSubresourceRange {
    uint aspectMask;
    uint baseMipLevel;
    uint levelCount;
    uint baseArrayLayer;
    uint layerCount;
}

struct VkApplicationInfo {
    VkStructureType sType;
    const(void)* pNext;
    const(char)* pApplicationName;
    uint applicationVersion;
    const(char)* pEngineName;
    uint engineVersion;
    uint apiVersion;
}

struct VkInstanceCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    const(VkApplicationInfo)* pApplicationInfo;
    uint enabledLayerCount;
    const(char*)* ppEnabledLayerNames;
    uint enabledExtensionCount;
    const(char*)* ppEnabledExtensionNames;
}

struct VkDeviceQueueCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    uint queueFamilyIndex;
    uint queueCount;
    const(float)* pQueuePriorities;
}

struct VkDeviceCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    uint queueCreateInfoCount;
    const(VkDeviceQueueCreateInfo)* pQueueCreateInfos;
    uint enabledLayerCount;
    const(char*)* ppEnabledLayerNames;
    uint enabledExtensionCount;
    const(char*)* ppEnabledExtensionNames;
    const(void)* pEnabledFeatures;
}

struct VkExtent3D {
    uint width;
    uint height;
    uint depth;
}

struct VkQueueFamilyProperties {
    uint queueFlags;
    uint queueCount;
    uint timestampValidBits;
    VkExtent3D minImageTransferGranularity;
}

struct VkSurfaceCapabilitiesKHR {
    uint minImageCount;
    uint maxImageCount;
    VkExtent2D currentExtent;
    VkExtent2D minImageExtent;
    VkExtent2D maxImageExtent;
    uint maxImageArrayLayers;
    uint supportedTransforms;
    uint currentTransform;
    uint supportedCompositeAlpha;
    uint supportedUsageFlags;
}

struct VkSurfaceFormatKHR {
    VkFormat format;
    VkColorSpaceKHR colorSpace;
}

struct VkSwapchainCreateInfoKHR {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    VkSurfaceKHR surface;
    uint minImageCount;
    VkFormat imageFormat;
    VkColorSpaceKHR imageColorSpace;
    VkExtent2D imageExtent;
    uint imageArrayLayers;
    uint imageUsage;
    VkSharingMode imageSharingMode;
    uint queueFamilyIndexCount;
    const(uint)* pQueueFamilyIndices;
    uint preTransform;
    uint compositeAlpha;
    VkPresentModeKHR presentMode;
    VkBool32 clipped;
    VkSwapchainKHR oldSwapchain;
}

struct VkImageViewCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    VkImage image;
    VkImageViewType viewType;
    VkFormat format;
    VkComponentMapping components;
    VkImageSubresourceRange subresourceRange;
}

struct VkAttachmentDescription {
    uint flags;
    VkFormat format;
    uint samples;
    VkAttachmentLoadOp loadOp;
    VkAttachmentStoreOp storeOp;
    VkAttachmentLoadOp stencilLoadOp;
    VkAttachmentStoreOp stencilStoreOp;
    VkImageLayout initialLayout;
    VkImageLayout finalLayout;
}

struct VkAttachmentReference {
    uint attachment;
    VkImageLayout layout;
}

struct VkSubpassDescription {
    uint flags;
    VkPipelineBindPoint pipelineBindPoint;
    uint inputAttachmentCount;
    const(VkAttachmentReference)* pInputAttachments;
    uint colorAttachmentCount;
    const(VkAttachmentReference)* pColorAttachments;
    const(VkAttachmentReference)* pResolveAttachments;
    const(void)* pDepthStencilAttachment;
    uint preserveAttachmentCount;
    const(uint)* pPreserveAttachments;
}

struct VkSubpassDependency {
    uint srcSubpass;
    uint dstSubpass;
    uint srcStageMask;
    uint dstStageMask;
    uint srcAccessMask;
    uint dstAccessMask;
    uint dependencyFlags;
}

struct VkRenderPassCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    uint attachmentCount;
    const(VkAttachmentDescription)* pAttachments;
    uint subpassCount;
    const(VkSubpassDescription)* pSubpasses;
    uint dependencyCount;
    const(VkSubpassDependency)* pDependencies;
}

struct VkFramebufferCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    VkRenderPass renderPass;
    uint attachmentCount;
    const(VkImageView)* pAttachments;
    uint width;
    uint height;
    uint layers;
}

struct VkCommandPoolCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    uint queueFamilyIndex;
}

struct VkCommandBufferAllocateInfo {
    VkStructureType sType;
    const(void)* pNext;
    VkCommandPool commandPool;
    VkCommandBufferLevel level;
    uint commandBufferCount;
}

struct VkCommandBufferBeginInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    const(void)* pInheritanceInfo;
}

struct VkRenderPassBeginInfo {
    VkStructureType sType;
    const(void)* pNext;
    VkRenderPass renderPass;
    VkFramebuffer framebuffer;
    VkRect2D renderArea;
    uint clearValueCount;
    const(VkClearValue)* pClearValues;
}

struct VkSemaphoreCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
}

struct VkFenceCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
}

struct VkSubmitInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint waitSemaphoreCount;
    const(VkSemaphore)* pWaitSemaphores;
    const(uint)* pWaitDstStageMask;
    uint commandBufferCount;
    const(VkCommandBuffer)* pCommandBuffers;
    uint signalSemaphoreCount;
    const(VkSemaphore)* pSignalSemaphores;
}

struct VkViewport {
    float x;
    float y;
    float width;
    float height;
    float minDepth;
    float maxDepth;
}

struct VkShaderModuleCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    size_t codeSize;
    const(uint)* pCode;
}

struct VkPipelineShaderStageCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    uint stage;
    VkShaderModule mod;
    const(char)* pName;
    const(void)* pSpecializationInfo;
}

struct VkVertexInputBindingDescription {
    uint binding;
    uint stride;
    VkVertexInputRate inputRate;
}

struct VkVertexInputAttributeDescription {
    uint location;
    uint binding;
    int format;
    uint offset;
}

struct VkPipelineVertexInputStateCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    uint vertexBindingDescriptionCount;
    const(VkVertexInputBindingDescription)* pVertexBindingDescriptions;
    uint vertexAttributeDescriptionCount;
    const(VkVertexInputAttributeDescription)* pVertexAttributeDescriptions;
}

struct VkPipelineInputAssemblyStateCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    VkPrimitiveTopology topology;
    VkBool32 primitiveRestartEnable;
}

struct VkPipelineViewportStateCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    uint viewportCount;
    const(VkViewport)* pViewports;
    uint scissorCount;
    const(VkRect2D)* pScissors;
}

struct VkPipelineRasterizationStateCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    VkBool32 depthClampEnable;
    VkBool32 rasterizerDiscardEnable;
    VkPolygonMode polygonMode;
    uint cullMode;
    VkFrontFace frontFace;
    VkBool32 depthBiasEnable;
    float depthBiasConstantFactor;
    float depthBiasClamp;
    float depthBiasSlopeFactor;
    float lineWidth;
}

struct VkPipelineMultisampleStateCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    uint rasterizationSamples;
    VkBool32 sampleShadingEnable;
    float minSampleShading;
    const(uint)* pSampleMask;
    VkBool32 alphaToCoverageEnable;
    VkBool32 alphaToOneEnable;
}

struct VkPipelineColorBlendAttachmentState {
    VkBool32 blendEnable;
    uint srcColorBlendFactor;
    uint dstColorBlendFactor;
    uint colorBlendOp;
    uint srcAlphaBlendFactor;
    uint dstAlphaBlendFactor;
    uint alphaBlendOp;
    uint colorWriteMask;
}

struct VkPipelineColorBlendStateCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    VkBool32 logicOpEnable;
    uint logicOp;
    uint attachmentCount;
    const(VkPipelineColorBlendAttachmentState)* pAttachments;
    float[4] blendConstants;
}

struct VkPipelineDynamicStateCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    uint dynamicStateCount;
    const(VkDynamicState)* pDynamicStates;
}

struct VkDescriptorSetLayoutBinding {
    uint binding;
    VkDescriptorType descriptorType;
    uint descriptorCount;
    uint stageFlags;
    const(void)* pImmutableSamplers;
}

struct VkDescriptorSetLayoutCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    uint bindingCount;
    const(VkDescriptorSetLayoutBinding)* pBindings;
}

struct VkDescriptorPoolSize {
    VkDescriptorType type;
    uint descriptorCount;
}

struct VkDescriptorPoolCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    uint maxSets;
    uint poolSizeCount;
    const(VkDescriptorPoolSize)* pPoolSizes;
}

struct VkDescriptorSetAllocateInfo {
    VkStructureType sType;
    const(void)* pNext;
    VkDescriptorPool descriptorPool;
    uint descriptorSetCount;
    const(VkDescriptorSetLayout)* pSetLayouts;
}

struct VkDescriptorBufferInfo {
    ulong buffer;
    VkDeviceSize offset;
    VkDeviceSize range;
}

struct VkWriteDescriptorSet {
    VkStructureType sType;
    const(void)* pNext;
    VkDescriptorSet dstSet;
    uint dstBinding;
    uint dstArrayElement;
    uint descriptorCount;
    VkDescriptorType descriptorType;
    const(void)* pImageInfo;
    const(VkDescriptorBufferInfo)* pBufferInfo;
    const(void)* pTexelBufferView;
}

struct VkPushConstantRange {
    uint stageFlags;
    uint offset;
    uint size;
}

struct VkPipelineLayoutCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    uint setLayoutCount;
    const(VkDescriptorSetLayout)* pSetLayouts;
    uint pushConstantRangeCount;
    const(VkPushConstantRange)* pPushConstantRanges;
}

struct VkComputePipelineCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    VkPipelineShaderStageCreateInfo stage;
    VkPipelineLayout layout;
    VkPipeline basePipelineHandle;
    int basePipelineIndex;
}

struct VkBufferMemoryBarrier {
    VkStructureType sType;
    const(void)* pNext;
    uint srcAccessMask;
    uint dstAccessMask;
    uint srcQueueFamilyIndex;
    uint dstQueueFamilyIndex;
    ulong buffer;
    VkDeviceSize offset;
    VkDeviceSize size;
}

struct VkGraphicsPipelineCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    uint stageCount;
    const(VkPipelineShaderStageCreateInfo)* pStages;
    const(VkPipelineVertexInputStateCreateInfo)* pVertexInputState;
    const(VkPipelineInputAssemblyStateCreateInfo)* pInputAssemblyState;
    const(void)* pTessellationState;
    const(VkPipelineViewportStateCreateInfo)* pViewportState;
    const(VkPipelineRasterizationStateCreateInfo)* pRasterizationState;
    const(VkPipelineMultisampleStateCreateInfo)* pMultisampleState;
    const(void)* pDepthStencilState;
    const(VkPipelineColorBlendStateCreateInfo)* pColorBlendState;
    const(VkPipelineDynamicStateCreateInfo)* pDynamicState;
    VkPipelineLayout layout;
    VkRenderPass renderPass;
    uint subpass;
    VkPipeline basePipelineHandle;
    int basePipelineIndex;
}

struct VkBufferCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    VkDeviceSize size;
    uint usage;
    VkSharingMode sharingMode;
    uint queueFamilyIndexCount;
    const(uint)* pQueueFamilyIndices;
}

struct VkMemoryRequirements {
    VkDeviceSize size;
    VkDeviceSize alignment;
    uint memoryTypeBits;
}

struct VkMemoryAllocateInfo {
    VkStructureType sType;
    const(void)* pNext;
    VkDeviceSize allocationSize;
    uint memoryTypeIndex;
}

struct VkMemoryType {
    uint propertyFlags;
    uint heapIndex;
}

struct VkMemoryHeap {
    VkDeviceSize size;
    uint flags;
}

struct VkPhysicalDeviceMemoryProperties {
    uint memoryTypeCount;
    VkMemoryType[32] memoryTypes;
    uint memoryHeapCount;
    VkMemoryHeap[16] memoryHeaps;
}

alias VkDeviceMemory = ulong;

struct VkPresentInfoKHR {
    VkStructureType sType;
    const(void)* pNext;
    uint waitSemaphoreCount;
    const(VkSemaphore)* pWaitSemaphores;
    uint swapchainCount;
    const(VkSwapchainKHR)* pSwapchains;
    const(uint)* pImageIndices;
    VkResult* pResults;
}

// SDL Vulkan functions (from libSDL3)
extern(C) nothrow @nogc {
    const(char)** SDL_Vulkan_GetInstanceExtensions(uint* count);
    bool SDL_Vulkan_CreateSurface(void* window, VkInstance instance, const(void)* allocator, VkSurfaceKHR* surface);
}

// Vulkan functions - linked from libvulkan.so
extern(C) nothrow @nogc {
    VkResult vkCreateInstance(const(VkInstanceCreateInfo)*, const(void)*, VkInstance*);
    void vkDestroyInstance(VkInstance, const(void)*);
    VkResult vkEnumeratePhysicalDevices(VkInstance, uint*, VkPhysicalDevice*);
    void vkGetPhysicalDeviceQueueFamilyProperties(VkPhysicalDevice, uint*, VkQueueFamilyProperties*);
    VkResult vkCreateDevice(VkPhysicalDevice, const(VkDeviceCreateInfo)*, const(void)*, VkDevice*);
    void vkDestroyDevice(VkDevice, const(void)*);
    void vkGetDeviceQueue(VkDevice, uint, uint, VkQueue*);
    void vkDestroySurfaceKHR(VkInstance, VkSurfaceKHR, const(void)*);
    VkResult vkGetPhysicalDeviceSurfaceCapabilitiesKHR(VkPhysicalDevice, VkSurfaceKHR, VkSurfaceCapabilitiesKHR*);
    VkResult vkGetPhysicalDeviceSurfaceFormatsKHR(VkPhysicalDevice, VkSurfaceKHR, uint*, VkSurfaceFormatKHR*);
    VkResult vkGetPhysicalDeviceSurfacePresentModesKHR(VkPhysicalDevice, VkSurfaceKHR, uint*, VkPresentModeKHR*);
    VkResult vkGetPhysicalDeviceSurfaceSupportKHR(VkPhysicalDevice, uint, VkSurfaceKHR, VkBool32*);
    VkResult vkCreateSwapchainKHR(VkDevice, const(VkSwapchainCreateInfoKHR)*, const(void)*, VkSwapchainKHR*);
    void vkDestroySwapchainKHR(VkDevice, VkSwapchainKHR, const(void)*);
    VkResult vkGetSwapchainImagesKHR(VkDevice, VkSwapchainKHR, uint*, VkImage*);
    VkResult vkCreateImageView(VkDevice, const(VkImageViewCreateInfo)*, const(void)*, VkImageView*);
    void vkDestroyImageView(VkDevice, VkImageView, const(void)*);
    VkResult vkCreateRenderPass(VkDevice, const(VkRenderPassCreateInfo)*, const(void)*, VkRenderPass*);
    void vkDestroyRenderPass(VkDevice, VkRenderPass, const(void)*);
    VkResult vkCreateFramebuffer(VkDevice, const(VkFramebufferCreateInfo)*, const(void)*, VkFramebuffer*);
    void vkDestroyFramebuffer(VkDevice, VkFramebuffer, const(void)*);
    VkResult vkCreateCommandPool(VkDevice, const(VkCommandPoolCreateInfo)*, const(void)*, VkCommandPool*);
    void vkDestroyCommandPool(VkDevice, VkCommandPool, const(void)*);
    VkResult vkAllocateCommandBuffers(VkDevice, const(VkCommandBufferAllocateInfo)*, VkCommandBuffer*);
    VkResult vkBeginCommandBuffer(VkCommandBuffer, const(VkCommandBufferBeginInfo)*);
    VkResult vkEndCommandBuffer(VkCommandBuffer);
    void vkCmdBeginRenderPass(VkCommandBuffer, const(VkRenderPassBeginInfo)*, VkSubpassContents);
    void vkCmdEndRenderPass(VkCommandBuffer);
    VkResult vkCreateSemaphore(VkDevice, const(VkSemaphoreCreateInfo)*, const(void)*, VkSemaphore*);
    void vkDestroySemaphore(VkDevice, VkSemaphore, const(void)*);
    VkResult vkCreateFence(VkDevice, const(VkFenceCreateInfo)*, const(void)*, VkFence*);
    void vkDestroyFence(VkDevice, VkFence, const(void)*);
    VkResult vkWaitForFences(VkDevice, uint, const(VkFence)*, VkBool32, ulong);
    VkResult vkResetFences(VkDevice, uint, const(VkFence)*);
    VkResult vkAcquireNextImageKHR(VkDevice, VkSwapchainKHR, ulong, VkSemaphore, VkFence, uint*);
    VkResult vkQueueSubmit(VkQueue, uint, const(VkSubmitInfo)*, VkFence);
    VkResult vkQueuePresentKHR(VkQueue, const(VkPresentInfoKHR)*);
    VkResult vkDeviceWaitIdle(VkDevice);
    VkResult vkResetCommandBuffer(VkCommandBuffer, uint);
    VkResult vkCreateShaderModule(VkDevice, const(VkShaderModuleCreateInfo)*, const(void)*, VkShaderModule*);
    void vkDestroyShaderModule(VkDevice, VkShaderModule, const(void)*);
    VkResult vkCreatePipelineLayout(VkDevice, const(VkPipelineLayoutCreateInfo)*, const(void)*, VkPipelineLayout*);
    void vkDestroyPipelineLayout(VkDevice, VkPipelineLayout, const(void)*);
    VkResult vkCreateGraphicsPipelines(VkDevice, ulong, uint, const(VkGraphicsPipelineCreateInfo)*, const(void)*, VkPipeline*);
    void vkDestroyPipeline(VkDevice, VkPipeline, const(void)*);
    VkResult vkCreateBuffer(VkDevice, const(VkBufferCreateInfo)*, const(void)*, ulong*);
    void vkDestroyBuffer(VkDevice, ulong, const(void)*);
    void vkGetBufferMemoryRequirements(VkDevice, ulong, VkMemoryRequirements*);
    VkResult vkCreateImage(VkDevice, const(VkImageCreateInfo)*, const(void)*, VkImage*);
    void vkDestroyImage(VkDevice, VkImage, const(void)*);
    void vkGetImageMemoryRequirements(VkDevice, VkImage, VkMemoryRequirements*);
    VkResult vkBindImageMemory(VkDevice, VkImage, VkDeviceMemory, VkDeviceSize);
    VkResult vkAllocateMemory(VkDevice, const(VkMemoryAllocateInfo)*, const(void)*, VkDeviceMemory*);
    void vkFreeMemory(VkDevice, VkDeviceMemory, const(void)*);
    VkResult vkBindBufferMemory(VkDevice, ulong, VkDeviceMemory, VkDeviceSize);
    VkResult vkMapMemory(VkDevice, VkDeviceMemory, VkDeviceSize, VkDeviceSize, uint, void**);
    void vkUnmapMemory(VkDevice, VkDeviceMemory);
    void vkGetPhysicalDeviceMemoryProperties(VkPhysicalDevice, VkPhysicalDeviceMemoryProperties*);
    void vkCmdBindPipeline(VkCommandBuffer, VkPipelineBindPoint, VkPipeline);
    void vkCmdBindVertexBuffers(VkCommandBuffer, uint, uint, const(ulong)*, const(VkDeviceSize)*);
    void vkCmdBindIndexBuffer(VkCommandBuffer, ulong, VkDeviceSize, VkIndexType);
    void vkCmdDraw(VkCommandBuffer, uint, uint, uint, uint);
    void vkCmdDrawIndexed(VkCommandBuffer, uint, uint, uint, int, uint);
    void vkCmdPushConstants(VkCommandBuffer, VkPipelineLayout, uint, uint, uint, const(void)*);
    void vkCmdSetViewport(VkCommandBuffer, uint, uint, const(VkViewport)*);
    void vkCmdSetScissor(VkCommandBuffer, uint, uint, const(VkRect2D)*);
    VkResult vkCreateDescriptorSetLayout(VkDevice, const(VkDescriptorSetLayoutCreateInfo)*, const(void)*, VkDescriptorSetLayout*);
    void vkDestroyDescriptorSetLayout(VkDevice, VkDescriptorSetLayout, const(void)*);
    VkResult vkCreateDescriptorPool(VkDevice, const(VkDescriptorPoolCreateInfo)*, const(void)*, VkDescriptorPool*);
    void vkDestroyDescriptorPool(VkDevice, VkDescriptorPool, const(void)*);
    VkResult vkAllocateDescriptorSets(VkDevice, const(VkDescriptorSetAllocateInfo)*, VkDescriptorSet*);
    void vkUpdateDescriptorSets(VkDevice, uint, const(VkWriteDescriptorSet)*, uint, const(void)*);
    void vkCmdBindDescriptorSets(VkCommandBuffer, VkPipelineBindPoint, VkPipelineLayout, uint, uint, const(VkDescriptorSet)*, uint, const(uint)*);
    VkResult vkCreateComputePipelines(VkDevice, ulong, uint, const(VkComputePipelineCreateInfo)*, const(void)*, VkPipeline*);
    void vkCmdDispatch(VkCommandBuffer, uint, uint, uint);
    void vkCmdFillBuffer(VkCommandBuffer, ulong, VkDeviceSize, VkDeviceSize, uint);
    void vkCmdPipelineBarrier(VkCommandBuffer, uint, uint, uint, uint, const(void)*, uint, const(VkBufferMemoryBarrier)*, uint, const(void)*);
    void vkCmdDrawIndirect(VkCommandBuffer, ulong, VkDeviceSize, uint, uint);
    void vkCmdNextSubpass(VkCommandBuffer, VkSubpassContents);
    VkResult vkCreateSampler(VkDevice, const(VkSamplerCreateInfo)*, const(void)*, VkSampler*);
    void vkDestroySampler(VkDevice, VkSampler, const(void)*);
    void vkCmdCopyBuffer(VkCommandBuffer, ulong, ulong, uint, const(VkBufferCopy)*);
    void vkCmdCopyBufferToImage(VkCommandBuffer, ulong, VkImage, int, uint, const(VkBufferImageCopy)*);
    VkResult vkQueueWaitIdle(VkQueue);
}

struct VkBufferCopy {
    VkDeviceSize srcOffset;
    VkDeviceSize dstOffset;
    VkDeviceSize size;
}

struct VkSamplerCreateInfo {
    VkStructureType sType;
    const(void)* pNext;
    uint flags;
    int magFilter;
    int minFilter;
    int mipmapMode;
    int addressModeU;
    int addressModeV;
    int addressModeW;
    float mipLodBias;
    VkBool32 anisotropyEnable;
    float maxAnisotropy;
    VkBool32 compareEnable;
    int compareOp;
    float minLod;
    float maxLod;
    int borderColor;
    VkBool32 unnormalizedCoordinates;
}

struct VkDescriptorImageInfo {
    VkSampler sampler;
    VkImageView imageView;
    int imageLayout;
}

struct VkImageMemoryBarrier {
    VkStructureType sType;
    const(void)* pNext;
    uint srcAccessMask;
    uint dstAccessMask;
    int oldLayout;
    int newLayout;
    uint srcQueueFamilyIndex;
    uint dstQueueFamilyIndex;
    VkImage image;
    VkImageSubresourceRange subresourceRange;
}

struct VkImageSubresourceLayers {
    uint aspectMask;
    uint mipLevel;
    uint baseArrayLayer;
    uint layerCount;
}

struct VkOffset3D {
    int x;
    int y;
    int z;
}

struct VkBufferImageCopy {
    VkDeviceSize bufferOffset;
    uint bufferRowLength;
    uint bufferImageHeight;
    VkImageSubresourceLayers imageSubresource;
    VkOffset3D imageOffset;
    VkExtent3D imageExtent;
}

enum VkPipelineBindPointCompute = 1;
enum VK_FILTER_NEAREST = 0;
enum VK_FILTER_LINEAR = 1;
enum VK_SAMPLER_MIPMAP_MODE_NEAREST = 0;
enum VK_SAMPLER_ADDRESS_MODE_REPEAT = 0;
enum VK_QUEUE_FAMILY_IGNORED = ~0U;
enum VK_ACCESS_TRANSFER_READ_BIT = 0x00000800;
enum VK_ACCESS_TRANSFER_WRITE_BIT = 0x00001000;
enum VK_DEPENDENCY_BY_REGION_BIT = 0x00000001;

enum VkBlendFactor : int {
    VK_BLEND_FACTOR_SRC_ALPHA = 6,
    VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA = 7,
}

enum VkBlendOp : int {
    VK_BLEND_OP_ADD = 0,
}
