require 'active_record'
require "custom_association/version"

class CustomAssociation::Preloader
  attr_reader :preloaded_records
  def initialize(klass, records, reflection, scope)
    @reflection = reflection
    @klass = klass
    @records = records
    @scope = scope
  end

  def run(_preloader)
    preloaded = @reflection.preloader.call @records
    @preloaded_records = @records.flat_map do |record|
      value = record.instance_exec preloaded, &@reflection.block
      record.association(@reflection.name).writer(value)
      value
    end
  end
end

module CustomAssociation::PreloaderExtension
  if ActiveRecord::Associations::Preloader.instance_method(:preloader_for).arity == 3
    def preloader_for(reflection, owners, rhs_klass)
      preloader = super
      return preloader if preloader
      return CustomAssociation::Preloader if reflection.macro == :has_custom_field
    end
  else
    def preloader_for(reflection, owners)
      return CustomAssociation::Preloader if reflection.macro == :has_custom_field
      super
    end
  end
end

class CustomAssociation::Association < ActiveRecord::Associations::Association
  def macro
    :has_custom_field
  end

  def writer value
    @loaded = true
    @value = value
  end

  def reader
    load unless @loaded
    @value
  end

  def load
    preloaded = @reflection.preloader.call [@owner]
    writer @owner.instance_exec preloaded, &@reflection.block
  end
end

class CustomAssociation::Reflection < ActiveRecord::Reflection::AssociationReflection
  attr_reader :preloader, :block
  def initialize(klass, name, preloader, block)
    @klass = klass
    @name = name
    @preloader = preloader
    @block = block || ->(preloaded) { preloaded[id] }
    @options = {}
  end

  def macro
    :has_custom_field
  end

  def association_class
    CustomAssociation::Association
  end
end

class << ActiveRecord::Base
  def has_custom_association(name, preloader:, &block)
    name = name.to_sym
    reflection = CustomAssociation::Reflection.new self, name, preloader, block
    ActiveRecord::Reflection.add_reflection self, name, reflection
    ActiveRecord::Associations::Builder::Association.define_readers(self, name)
  end
end

ActiveRecord::Associations::Preloader.prepend CustomAssociation::PreloaderExtension
