require 'spec_helper'

require 'bot/parameter_parsing'

describe ParameterParsing do
  let(:vessel) do
    Object.new.extend(ParameterParsing)
  end

  it 'parses the empty string to {}' do
    vessel.parse_params('').should == {}
  end

  it 'parses foo to {}' do
    vessel.parse_params('foo').should == {}
  end

  it 'parses --foo to {}' do
    vessel.parse_params('--foo').should == {}
  end

  it 'parses --foo= to {}' do
    vessel.parse_params('--foo').should == {}
  end

  it 'parses --foo= --bar to {}' do
    vessel.parse_params('--foo= --bar').should == {}
  end

  it 'parses --foo=--bar to foo = --bar' do
    vessel.parse_params('--foo=--bar').should == { 'foo' => ['--bar'] }
  end

  it 'parses --foo-bar=baz to foo_bar = [baz]' do
    vessel.parse_params('--foo-bar=baz').should == { 'foo_bar' => ['baz'] }
  end

  it 'parses --foo-bar=baz,qux to foo_bar = [baz, qux]' do
    vessel.parse_params('--foo-bar=baz,qux').should == { 'foo_bar' => ['baz', 'qux'] }
  end

  it 'parses --foo=baz --bar=qux to foo = [baz], bar = [qux]' do
    vessel.parse_params('--foo=baz --bar=qux').should == {
      'foo' => ['baz'], 'bar' => ['qux']
    }
  end
end
